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
}

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

export function buildMemberEvents(
  spaceId: string,
  memberUid: string,
  before: Doc,
  after: Doc,
  spaceName: string,
  audience: string[],
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
    // La app marca `removedBy` (validado por Rules como el owner) en el
    // mismo batch del borrado: distingue expulsión de salida voluntaria.
    const removedBy = before.removedBy as string | undefined;
    return [{
      id: `mb_${spaceId}_${memberUid}_left_${asMillis(before.joinedAt)}`,
      type: removedBy ? 'member_removed' : 'member_left',
      actorUid: removedBy ?? memberUid,
      memberUids: activityAudience([...audience, memberUid]),
      spaceId,
      summary,
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

export function buildTicketEvents(
  sessionId: string,
  ticketId: string,
  before: Doc,
  after: Doc,
  actorUid: string,
  audience: string[],
  sessionName: string,
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
    return [{ ...base, id: `tk_${sessionId}_${ticketId}_deleted`, type: 'ticket_deleted' }];
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

  const beforeRelevant = relevantTicketFields(before);
  const afterRelevant = relevantTicketFields(after);
  if (JSON.stringify(beforeRelevant) !== JSON.stringify(afterRelevant)) {
    // UNA edición atómica = UN evento; el id deriva del estado destino, así
    // que los reintentos del trigger no duplican nada.
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
        at: FieldValue.serverTimestamp(),
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
    const [space, audience] = await Promise.all([
      db.doc(`spaces/${spaceId}`).get(),
      spaceAudience(spaceId),
    ]);
    if (!space.exists) return; // limpieza huérfana: sin espacio no hay feed
    await persistEvents(buildMemberEvents(
      spaceId,
      memberUid,
      event.data?.before?.data(),
      event.data?.after?.data(),
      (space.data()?.name as string) ?? '',
      audience,
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

    const uids = [context.ownerUid, ...context.registered.values()];
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
      context.ownerUid, // solo el dueño de la sesión escribe tickets (Rules)
      activityAudience(uids),
      context.name,
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
