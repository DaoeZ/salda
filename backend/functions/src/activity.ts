/**
 * P6 — Actividad (docs/ACTIVIDAD.md, ADR-031).
 *
 * El feed es una PROYECCIÓN de auditoría, nunca la fuente de verdad: los
 * hechos viven en espacios, membresías, invitaciones, tickets, settlements
 * y pagos P5. Todos los eventos los generan estos triggers Admin (ningún
 * cliente puede escribir actividad ni suplantar a un actor) con IDs
 * DETERMINISTAS derivados del hecho: un reintento del trigger, una escritura
 * offline repetida o un recompute reescribiendo proyecciones convergen en el
 * MISMO documento (create-only: el primero gana y conserva su hora).
 *
 * La audiencia (`memberUids`) se CONGELA en el momento del hecho: un miembro
 * nuevo no hereda actividad anterior y un expulsado conserva la lectura de
 * los hechos en los que participó. Los nombres de personas NO se guardan:
 * se resuelven en vivo por UID; solo se congela el rótulo del objeto
 * (espacio/ticket) para que el histórico siga siendo legible si desaparece.
 */
import { createHash } from 'node:crypto';

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

export type ActivityType =
  | 'space_created'
  | 'space_renamed'
  | 'space_archived'
  | 'space_reactivated'
  | 'space_transferred'
  | 'invite_sent'
  | 'member_joined'
  | 'member_left'
  | 'member_removed'
  | 'ticket_created'
  | 'ticket_updated'
  | 'ticket_linked'
  | 'ticket_unlinked'
  | 'ticket_deleted'
  | 'payment_marked'
  | 'payment_confirmed'
  | 'payment_cancelled';

export interface ActivityEventDraft {
  id: string;
  type: ActivityType;
  actorUid: string;
  /** Audiencia congelada del hecho; siempre incluye al actor si tiene UID. */
  memberUids: string[];
  spaceId?: string;
  sessionId?: string;
  ticketId?: string;
  paymentId?: string;
  /** Datos visuales mínimos (rótulos e importes), jamás datos privados. */
  summary: Record<string, string | number>;
  /**
   * Instante REAL del hecho, cuando existe un documento autoritativo que lo
   * fecha (A11d: `removals.removedAt`). Sin él se sella la hora de proceso,
   * que para un trigger retrasado colocaría el hecho en el sitio equivocado
   * de la cronología.
   */
  at?: unknown;
}

/**
 * Identidad del CICLO de membresía (A11d): `{uid}_{joinedAtMillis}`.
 *
 * Se deriva del `before` INMUTABLE del evento, así que un trigger retrasado
 * —o reintentado después de una readmisión, o después de una segunda
 * expulsión— sigue apuntando al documento del ciclo que está clasificando.
 * Debe coincidir exactamente con `membershipCycleId` de firestore.rules.
 */
export const membershipCycleId = (uid: string, joinedAt: unknown): string =>
  `${uid}_${asMillis(joinedAt)}`;

/** Máximo de UIDs por evento: techo documentado de escalabilidad. */
export const activityAudienceLimit = 30;

const hash12 = (text: string): string =>
  createHash('sha256').update(text, 'utf8').digest('hex').slice(0, 12);

/** Audiencia normalizada: única, ordenada, acotada y sin vacíos. */
export function activityAudience(uids: Iterable<string>): string[] {
  return [...new Set([...uids].filter((uid) => uid.length > 0))]
    .sort()
    .slice(0, activityAudienceLimit);
}

type Doc = Record<string, unknown> | undefined;

const asMillis = (value: unknown): number => {
  const maybe = value as { toMillis?: () => number } | undefined;
  return typeof maybe?.toMillis === 'function' ? maybe.toMillis() : 0;
};

// ── Builders puros (testeables sin Firestore) ──────────────────────────────

export function buildSpaceEvents(
  spaceId: string,
  before: Doc,
  after: Doc,
  audience: string[],
): ActivityEventDraft[] {
  if (!after) return []; // los espacios no se borran (P4)
  const name = (after.name as string) ?? '';
  const stamp = asMillis(after.updatedAt);
  const base = { spaceId, memberUids: audience, summary: { spaceName: name } };

  if (!before) {
    return [{
      ...base,
      id: `sp_${spaceId}_created`,
      type: 'space_created',
      actorUid: (after.ownerUid as string) ?? '',
    }];
  }

  const events: ActivityEventDraft[] = [];
  if (before.ownerUid !== after.ownerUid) {
    // La transferencia la inicia el owner ANTERIOR (regla de P4).
    events.push({
      ...base,
      id: `sp_${spaceId}_transfer_${stamp}`,
      type: 'space_transferred',
      actorUid: (before.ownerUid as string) ?? '',
    });
  }
  if (before.status !== after.status) {
    events.push({
      ...base,
      id: `sp_${spaceId}_${after.status === 'archived' ? 'arch' : 'react'}_${stamp}`,
      type: after.status === 'archived' ? 'space_archived' : 'space_reactivated',
      actorUid: (after.ownerUid as string) ?? '',
    });
  }
  if (
    before.ownerUid === after.ownerUid &&
    (before.name !== after.name || before.avatarEmoji !== after.avatarEmoji)
  ) {
    events.push({
      ...base,
      id: `sp_${spaceId}_renamed_${stamp}`,
      type: 'space_renamed',
      actorUid: (after.ownerUid as string) ?? '',
    });
  }
  return events;
}

/**
 * [removal] es la evidencia INMUTABLE de la expulsión de ESTE ciclo
 * (`spaces/{id}/removals/{uid}_{joinedAtMillis}`), o `undefined` si no
 * existe. Es el único discriminador entre expulsión y salida voluntaria, y
 * es seguro precisamente porque no puede envejecer: Rules exige escribirla
 * en el MISMO commit que el borrado, así que «no hay evidencia» significa
 * «no la habrá nunca», no «todavía no ha llegado» (A11d/ADR-039).
 */
export function buildMemberEvents(
  spaceId: string,
  memberUid: string,
  before: Doc,
  after: Doc,
  spaceName: string,
  audience: string[],
  removal?: Doc,
): ActivityEventDraft[] {
  const summary = { spaceName };
  if (!before && after) {
    return [{
      id: `mb_${spaceId}_${memberUid}_join_${asMillis(after.joinedAt)}`,
      type: 'member_joined',
      actorUid: memberUid, // unirse es siempre un acto propio (aceptar)
      memberUids: audience,
      spaceId,
      summary,
    }];
  }
  if (before && !after) {
    // El id conserva su formato histórico y ya lleva el ciclo dentro
    // (`joinedAt`), así que dos entradas y dos salidas de la misma persona
    // nunca se pisan. El TIPO va en el campo, no en el id: cambiarlo sería
    // fabricar duplicados alrededor de despliegues y reintentos.
    return [{
      id: `mb_${spaceId}_${memberUid}_left_${asMillis(before.joinedAt)}`,
      type: removal ? 'member_removed' : 'member_left',
      actorUid: (removal?.removedBy as string | undefined) ?? memberUid,
      memberUids: activityAudience([...audience, memberUid]),
      spaceId,
      summary,
      ...(removal?.removedAt ? { at: removal.removedAt } : {}),
    }];
  }
  return [];
}

export function buildInviteEvents(
  inviteId: string,
  before: Doc,
  after: Doc,
): ActivityEventDraft[] {
  // Solo el envío (o reenvío) aporta valor; rechazos y cancelaciones son
  // privados entre las partes y no se publican (espec. P6).
  if (!after || after.status !== 'pending') return [];
  if (before && before.status === 'pending') return [];
  const fromUid = (after.fromUid as string) ?? '';
  const toUid = (after.toUid as string) ?? '';
  return [{
    id: `inv_${inviteId}_${asMillis(after.updatedAt)}`,
    type: 'invite_sent',
    actorUid: fromUid,
    memberUids: activityAudience([fromUid, toUid]),
    spaceId: (after.spaceId as string) ?? undefined,
    summary: { spaceName: (after.spaceName as string) ?? '' },
  }];
}

/** Campos cuyo cambio hace a una edición de ticket "relevante" para el feed. */
const relevantTicketFields = (data: Doc) => ({
  merchant: ((data?.merchant as { name?: string } | undefined)?.name) ?? '',
  grandTotal: (data?.grandTotal as number) ?? 0,
  date: (data?.date as string) ?? '',
  paidBy: (data?.paidByParticipantId as string) ?? '',
});

/**
 * Firma de la corrección administrativa (A11c): `quién@cuándo`, o cadena
 * vacía si el ticket no lleva ninguna.
 *
 * Es un VALOR, no un booleano, y ahí está la gracia: comparar la firma de
 * `before` con la de `after` distingue «esta escritura ES una corrección»
 * de «el ticket conserva la firma de una corrección anterior». Sin esa
 * comparación, cualquier escritura posterior no firmada se atribuiría para
 * siempre al último que corrigió, que es exactamente el error que P6 no
 * puede permitirse: un actor inventado en un registro de auditoría.
 */
function correctionSignature(data: Doc): string {
  const by = (data?.lastEditedByUid as string) ?? '';
  const at = data?.lastEditedAt;
  if (by === '' || at == null) return '';
  const millis = at instanceof Date
    ? at.getTime()
    : typeof at === 'number'
      ? at
      : typeof (at as { toMillis?: () => number }).toMillis === 'function'
        ? (at as { toMillis: () => number }).toMillis()
        : Number.NaN;
  return Number.isNaN(millis) ? '' : `${by}@${millis}`;
}

/** Evidencia de eliminación (A2): quién borró el gasto y cuándo. */
export interface TicketRemovalEvidence {
  removedBy: string;
  removedAt: unknown;
}

export function buildTicketEvents(
  sessionId: string,
  ticketId: string,
  before: Doc,
  after: Doc,
  actorUid: string,
  audience: string[],
  sessionName: string,
  removal?: TicketRemovalEvidence,
): ActivityEventDraft[] {
  const data = after ?? before;
  const ticketName =
    ((data?.merchant as { name?: string } | undefined)?.name) || sessionName;
  const base = {
    actorUid,
    memberUids: audience,
    sessionId,
    ticketId,
    summary: {
      ticketName,
      sessionName,
      amount: (data?.grandTotal as number) ?? 0,
      currency: 'EUR',
    },
    spaceId: ((after ?? before)?.spaceId as string) || undefined,
  };

  if (!before && after) {
    return [{ ...base, id: `tk_${sessionId}_${ticketId}_created`, type: 'ticket_created' }];
  }
  if (before && !after) {
    // A2: el actor NO es el dueño de la sesión por defecto — quien administra
    // el grupo puede borrar el gasto de otra persona, y atribuírselo a ella
    // sería falso y PERMANENTE (`persistEvents` usa create-only). El actor y
    // la hora salen de la evidencia inmutable, así que un trigger reintentado
    // o retrasado obtiene siempre los mismos. Sin evidencia no se puede
    // llegar aquí: Rules la exigen en el mismo commit que el borrado.
    return [{
      ...base,
      ...(removal
        ? { actorUid: removal.removedBy, at: removal.removedAt }
        : {}),
      id: `tk_${sessionId}_${ticketId}_deleted`,
      type: 'ticket_deleted',
    }];
  }
  if (!before || !after) return [];

  const events: ActivityEventDraft[] = [];
  const beforeSpace = (before.spaceId as string) ?? '';
  const afterSpace = (after.spaceId as string) ?? '';
  if (beforeSpace !== afterSpace) {
    const linked = afterSpace !== '';
    events.push({
      ...base,
      spaceId: linked ? afterSpace : beforeSpace,
      id: `tk_${sessionId}_${ticketId}_${linked ? 'link' : 'unlink'}_${
        hash12(afterSpace || beforeSpace)}`,
      type: linked ? 'ticket_linked' : 'ticket_unlinked',
    });
  }

  // ── Corrección administrativa firmada (A11c) ──────────────────────────
  // La firma solo la renueva una corrección, y viaja en el MISMO batch que
  // el cambio de las líneas. Por eso sirve de señal agregada: una operación
  // toca el ticket una vez, deje o no rastro en `relevantTicketFields`, y
  // produce UN evento — también cuando lo corregido fueron solo productos,
  // que es justo lo que este feed no llegaba a contar.
  const signature = correctionSignature(after);
  if (signature !== '' && signature !== correctionSignature(before)) {
    events.push({
      ...base,
      // El actor es quien firma ESTA corrección, no el dueño de la sesión:
      // desde A11c ya no son necesariamente la misma persona.
      actorUid: (after.lastEditedByUid as string),
      // El id deriva de la firma (uid + instante), no del estado destino:
      // reintentar el mismo write da el mismo id —idempotente— pero dos
      // correcciones distintas que acaben en el mismo importe (30 → 3 → 30)
      // ya no se pisan la una a la otra en el histórico.
      id: `tk_${sessionId}_${ticketId}_upd_${hash12(signature)}`,
      type: 'ticket_updated',
    });
    return events;
  }

  const beforeRelevant = relevantTicketFields(before);
  const afterRelevant = relevantTicketFields(after);
  if (JSON.stringify(beforeRelevant) !== JSON.stringify(afterRelevant)) {
    // Escritura NO firmada (el dueño desde los flujos de siempre): actor y
    // id se mantienen exactamente como estaban. El id deriva del estado
    // destino, así que los reintentos del trigger no duplican nada.
    events.push({
      ...base,
      id: `tk_${sessionId}_${ticketId}_upd_${hash12(JSON.stringify(afterRelevant))}`,
      type: 'ticket_updated',
    });
  }
  return events;
}

export function buildSettlementEvents(
  sessionId: string,
  settlementId: string,
  before: Doc,
  after: Doc,
  resolveUid: (pid: string) => string | undefined,
  audience: string[],
  sessionName: string,
  currency: string,
): ActivityEventDraft[] {
  // Solo transiciones HUMANAS reales: recompute crea/regenera únicamente
  // `pending` (una sugerencia no es un pago) y jamás escribe marked ni
  // confirmed, así que un recálculo no puede fabricar eventos.
  if (!after || before?.state === after.state) return [];
  const state = after.state as string;
  if (state !== 'marked' && state !== 'confirmed') return [];
  const fromUid = resolveUid((after.from as string) ?? '');
  const toUid = resolveUid((after.to as string) ?? '');
  const actorUid = state === 'marked' ? fromUid : toUid;
  if (!actorUid) return []; // sin identidad real no se inventa un actor
  return [{
    id: `st_${sessionId}_${settlementId}_${state}`,
    type: state === 'marked' ? 'payment_marked' : 'payment_confirmed',
    actorUid,
    memberUids: activityAudience(
      [fromUid, toUid].filter((uid): uid is string => Boolean(uid))
        .concat(audience),
    ),
    sessionId,
    summary: {
      sessionName,
      amount: (after.amount as number) ?? 0,
      currency,
    },
  }];
}

export function buildEconomicPaymentEvents(
  paymentId: string,
  before: Doc,
  after: Doc,
): ActivityEventDraft[] {
  // Los pagos legacy son proyecciones que recompute reescribe: su hecho ya
  // se registra desde el settlement humano. Aquí SOLO pagos P5 de usuario.
  if (!after || after.source !== 'user') return [];
  if (before?.status === after.status) return [];
  const status = after.status as string;
  const history = (after.stateHistory as Array<{ byUid?: string }>) ?? [];
  const actorUid = history.at(-1)?.byUid as string | undefined;
  const type: ActivityType | undefined = status === 'pending'
    ? 'payment_marked'
    : status === 'confirmed'
      ? 'payment_confirmed'
      : status === 'cancelled'
        ? 'payment_cancelled'
        : undefined;
  if (!type || !actorUid) return [];
  return [{
    id: `pay_${hash12(paymentId)}_${status}`,
    type,
    actorUid,
    memberUids: activityAudience((after.memberUids as string[]) ?? []),
    paymentId,
    summary: {
      amount: (after.amount as number) ?? 0,
      currency: (after.currency as string) ?? 'EUR',
    },
  }];
}

// ── Escritura idempotente ──────────────────────────────────────────────────

export async function persistEvents(
  drafts: ActivityEventDraft[],
): Promise<void> {
  if (drafts.length === 0) return;
  const db = getFirestore();
  await Promise.all(drafts.map(async (draft) => {
    try {
      // create(): si el evento ya existe (reintento, recompute, doble
      // trigger) el primero gana y conserva su hora real.
      await db.collection('activityEvents').doc(draft.id).create({
        type: draft.type,
        actorUid: draft.actorUid,
        memberUids: draft.memberUids,
        ...(draft.spaceId ? { spaceId: draft.spaceId } : {}),
        ...(draft.sessionId ? { sessionId: draft.sessionId } : {}),
        ...(draft.ticketId ? { ticketId: draft.ticketId } : {}),
        ...(draft.paymentId ? { paymentId: draft.paymentId } : {}),
        summary: draft.summary,
        at: draft.at ?? FieldValue.serverTimestamp(),
        schemaVersion: 1,
      });
    } catch (error) {
      const code = (error as { code?: number }).code;
      if (code !== 6) throw error; // 6 = ALREADY_EXISTS → idempotente
    }
  }));
}

// ── Triggers ───────────────────────────────────────────────────────────────

async function spaceAudience(spaceId: string): Promise<string[]> {
  const members = await getFirestore()
    .collection(`spaces/${spaceId}/members`)
    .get();
  return activityAudience(members.docs.map((doc) => doc.id));
}

export const activityOnSpace = onDocumentWritten(
  'spaces/{spaceId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const audience = await spaceAudience(event.params.spaceId);
    await persistEvents(
      buildSpaceEvents(event.params.spaceId, before, after, audience),
    );
  },
);

export const activityOnSpaceMember = onDocumentWritten(
  'spaces/{spaceId}/members/{memberUid}',
  async (event) => {
    const { spaceId, memberUid } = event.params;
    const db = getFirestore();
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    // A11d: la ruta de la evidencia se deriva del payload del evento, no del
    // estado actual del usuario. Da igual cuándo llegue este trigger ni por
    // qué ciclo vaya ya la persona: siempre lee el documento de SU ciclo.
    const removalRef = before && !after
      ? db.doc(
        `spaces/${spaceId}/removals/${
          membershipCycleId(memberUid, before.joinedAt)}`)
      : null;
    const [space, audience, removal] = await Promise.all([
      db.doc(`spaces/${spaceId}`).get(),
      spaceAudience(spaceId),
      removalRef ? removalRef.get() : Promise.resolve(null),
    ]);
    if (!space.exists) return; // limpieza huérfana: sin espacio no hay feed
    await persistEvents(buildMemberEvents(
      spaceId,
      memberUid,
      before,
      after,
      (space.data()?.name as string) ?? '',
      audience,
      removal?.exists ? removal.data() : undefined,
    ));
  },
);

export const activityOnSpaceInvite = onDocumentWritten(
  'spaceInvites/{inviteId}',
  async (event) => {
    await persistEvents(buildInviteEvents(
      event.params.inviteId,
      event.data?.before?.data(),
      event.data?.after?.data(),
    ));
  },
);

interface SessionContext {
  name: string;
  ownerUid: string;
  currency: string;
  registered: Map<string, string>; // pid → uid con cuenta
}

async function sessionContext(sid: string): Promise<SessionContext | null> {
  const db = getFirestore();
  const [session, participants] = await Promise.all([
    db.doc(`sessions/${sid}`).get(),
    db.collection(`sessions/${sid}/participants`).get(),
  ]);
  if (!session.exists) return null;
  const ownerUid = (session.data()?.ownerUid as string) ?? '';
  const registered = new Map<string, string>();
  for (const doc of participants.docs) {
    const data = doc.data();
    const uid = (data.userUid as string | undefined) ??
      (data.isOwner === true ? ownerUid : undefined) ??
      (data.claimedByDevice as string | undefined);
    if (uid) registered.set(doc.id, uid);
  }
  return {
    name: (session.data()?.name as string) ?? '',
    ownerUid,
    currency: (session.data()?.currency as string) ?? 'EUR',
    registered,
  };
}

export const activityOnTicketWrite = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}',
  async (event) => {
    const { sid, tid } = event.params;
    const context = await sessionContext(sid);
    if (!context) return; // sesión borrada: cleanup manda
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // A2: la evidencia del borrado se lee ANTES de construir el evento y por
    // su ruta determinista, no por el `before` del ticket: es el único
    // documento del commit que sobrevive y sabe quién borró.
    const removal = before && !after
      ? (await getFirestore()
        .doc(`sessions/${sid}/ticketRemovals/${tid}`).get()).data()
      : undefined;

    const uids = [context.ownerUid, ...context.registered.values()];
    // Quien corrige puede no ser participante del gasto (A11c): entra en la
    // audiencia para que su propio hecho no le quede invisible. Lo mismo
    // vale para quien borra (A2).
    const signer = (after?.lastEditedByUid as string) ?? '';
    if (signer) uids.push(signer);
    const remover = (removal?.removedBy as string) ?? '';
    if (remover) uids.push(remover);
    const spaceId = ((after ?? before)?.spaceId as string) || '';
    if (spaceId) {
      try {
        uids.push(...await spaceAudience(spaceId));
      } catch (error) {
        logger.warn('Audiencia de espacio no disponible', { spaceId, error });
      }
    }

    await persistEvents(buildTicketEvents(
      sid,
      tid,
      before,
      after,
      // Actor POR DEFECTO. Una corrección firmada (A11c) lo sustituye por
      // quien la firma: desde entonces el dueño de la sesión ya no es el
      // único que puede escribir un ticket.
      context.ownerUid,
      activityAudience(uids),
      context.name,
      remover
        ? { removedBy: remover, removedAt: removal?.removedAt }
        : undefined,
    ));
  },
);

export const activityOnSettlementWrite = onDocumentWritten(
  'sessions/{sid}/settlements/{stid}',
  async (event) => {
    const { sid, stid } = event.params;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    // Filtro barato ANTES de leer nada: solo transiciones humanas.
    if (!after || before?.state === after.state) return;
    if (after.state !== 'marked' && after.state !== 'confirmed') return;
    const context = await sessionContext(sid);
    if (!context) return;
    await persistEvents(buildSettlementEvents(
      sid,
      stid,
      before,
      after,
      (pid) => context.registered.get(pid),
      [context.ownerUid],
      context.name,
      context.currency,
    ));
  },
);

export const activityOnEconomicPaymentWrite = onDocumentWritten(
  'economicPayments/{paymentId}',
  async (event) => {
    await persistEvents(buildEconomicPaymentEvents(
      event.params.paymentId,
      event.data?.before?.data(),
      event.data?.after?.data(),
    ));
  },
);
