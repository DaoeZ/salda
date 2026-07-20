/**
 * recompute — la calculadora autoritativa (spec §12.2, DC-7).
 *
 * Se dispara al escribir líneas, tickets o participantes y recalcula:
 * totales por cuenta, totales/balances de sesión y liquidaciones pendientes.
 * Escribe SOLO si algo cambió (sin cambio no hay bump de computeVersion →
 * sin cascadas). Determinista: ejecuciones concurrentes convergen al mismo
 * resultado. Usa los MISMOS motores validados por vectores dorados.
 *
 * Robustez ante datos huérfanos (participante borrado con asignaciones o
 * pagos colgando): se sanea (se ignoran pids desconocidos; un pagador
 * desconocido se reasigna al participante-owner) y se deja constancia en logs.
 */
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  computeBalance,
  type FrozenSettlement,
  type ParticipantBalance,
  type SettlementDraft,
  type TicketContribution,
} from './domain/balanceEngine.js';
import type { Cents } from './domain/money.js';
import {
  splitTicket,
  unitsFromQuantityMilli,
  type SplitLine,
  type SplitMode,
} from './domain/splitEngine.js';

// ── Modelo en memoria (independiente de Firestore para poder testearlo) ──

export interface ParticipantDoc {
  id: string;
  isOwner?: boolean;
  active?: boolean;
  order?: number;
  /** P5: identidad registrada estable. No confundir con claimedByDevice. */
  userUid?: string;
  claimedByDevice?: string;
}

export interface LineDoc {
  id: string;
  totalPrice: Cents;
  /** Cantidad ×1000; define las unidades reclamables de la línea (P2.1). */
  quantityMilli?: number;
  assignment?: {
    type?: string;
    participants?: Record<string, number>;
    schemaVersion?: number;
    units?: Record<string, Record<string, boolean | number>>;
  };
}

export interface TicketDoc {
  id: string;
  grandTotal: Cents;
  paidByParticipantId: string;
  splitModeOverride?: SplitMode;
  merchantName?: string;
  date?: string;
  spaceId?: string;
  lines: LineDoc[];
}

export interface AccountDoc {
  id: string;
  name?: string;
  tickets: TicketDoc[];
}

export interface SettlementDoc {
  id: string;
  from: string;
  to: string;
  amount: Cents;
  state: 'pending' | 'marked' | 'confirmed';
}

export interface SessionSnapshot {
  splitModeDefault: SplitMode;
  ownerUid?: string;
  currency?: string;
  participants: ParticipantDoc[];
  accounts: AccountDoc[];
  settlements: SettlementDoc[];
  /** Pagos P5 confirmados que afectan a tickets de esta sesión. */
  externalConfirmed?: Array<{ from: string; to: string; amount: Cents }>;
}

export interface RecomputeResult {
  accountTotals: Record<string, { grandTotal: Cents }>;
  sessionTotals: {
    grandTotal: Cents;
    /**
     * Importe total del ciclo de liquidación: pagos ya confirmados más las
     * obligaciones residuales que siguen siendo necesarias. Es el
     * denominador autoritativo del progreso; nunca se compara contra el gasto.
     */
    settlementRequired: Cents;
    settledConfirmed: Cents;
    settledMarked: Cents;
  };
  balances: Record<string, ParticipantBalance>;
  pendingSettlements: number;
  settlementSync: {
    /**
     * Docs a escribir con ID DETERMINISTA `pending_{from}_{to}`.
     * Clave del diseño: N recomputes concurrentes (uno por línea de un
     * batch) escriben el MISMO doc con el MISMO contenido → imposible
     * duplicar liquidaciones (la causa raíz del bug de pagos duplicados).
     */
    writes: SettlementDraft[];
    /** Ids que coinciden exactamente con el objetivo: NO se tocan
     * (preserva el estado `marked` del invitado). */
    untouched: string[];
    /** Ids no confirmados que ya no corresponden a ningún objetivo
     * (incluye docs legacy con id aleatorio). */
    removals: string[];
  };
  /** Obligaciones originales por ticket, reconstruibles y explicables. */
  economicEntries: EconomicEntryDraft[];
  /** Espejo de pagos legacy confirmados/pendientes con participantes UID. */
  legacyPayments: LegacyPaymentDraft[];
}

export interface EconomicEntryDraft {
  id: string;
  memberUids: [string, string];
  debtorUid: string;
  creditorUid: string;
  amount: Cents;
  currency: string;
  accountId: string;
  ticketId: string;
  ticketName: string;
  ticketDate?: string;
  spaceId?: string;
}

export interface LegacyPaymentDraft {
  id: string;
  memberUids: [string, string];
  payerUid: string;
  receiverUid: string;
  amount: Cents;
  currency: string;
  status: 'pending' | 'confirmed';
  settlementId: string;
}

/** Id determinista de una liquidación pendiente. */
export const settlementId = (draft: SettlementDraft): string =>
    `pending_${draft.from}_${draft.to}`;

const orderedUids = (left: string, right: string): [string, string] =>
  left < right ? [left, right] : [right, left];

const encodedPair = (left: string, right: string): string =>
  orderedUids(left, right)
    .map((uid) => Buffer.from(uid, 'utf8').toString('hex'))
    .join('_');

/**
 * Núcleo puro del recompute (testeable sin Firestore).
 *
 * Orden de participantes = campo `order` (índice de inserción que escribe la
 * app) con desempate por id: DEBE coincidir con el orden que usa la app en su
 * cálculo optimista para que ambos redondeos sean idénticos.
 */
export function computeAggregates(s: SessionSnapshot): RecomputeResult {
  const participants = [...s.participants].sort(
    (a, b) =>
      (a.order ?? Number.MAX_SAFE_INTEGER) -
        (b.order ?? Number.MAX_SAFE_INTEGER) || a.id.localeCompare(b.id),
  );
  const activeIds = participants
    .filter((p) => p.active !== false)
    .map((p) => p.id);
  const known = new Set(activeIds);
  const fallbackPayer =
    participants.find((p) => p.isOwner)?.id ?? activeIds[0];
  const currency = s.currency ?? 'EUR';
  const uidByPid = new Map<string, string>();
  for (const participant of participants) {
    const resolved = participant.userUid ??
      (participant.isOwner ? s.ownerUid : undefined);
    if (resolved) uidByPid.set(participant.id, resolved);
  }

  const accountTotals: RecomputeResult['accountTotals'] = {};
  const contributions: TicketContribution[] = [];
  const economicEntries: EconomicEntryDraft[] = [];

  for (const account of s.accounts) {
    let accountTotal = 0;
    for (const ticket of account.tickets) {
      accountTotal += ticket.grandTotal;
      const mode = ticket.splitModeOverride ?? s.splitModeDefault;

      // El pagador efectivo se resuelve ANTES de repartir: en "cada uno paga
      // lo suyo", las líneas aún NO reclamadas recaen sobre quien pagó (ver
      // sanitizeLine), nunca se promedian entre todos.
      let paidBy = ticket.paidByParticipantId;
      if (!known.has(paidBy)) {
        logger.warn('Pagador desconocido; se reasigna al owner', {
          ticket: ticket.id,
          paidBy,
        });
        paidBy = fallbackPayer;
      }

      const consumption = splitTicket({
        participantIds: activeIds,
        mode,
        ticket: {
          grandTotal: ticket.grandTotal,
          lines: ticket.lines.map((l) => sanitizeLine(l, known, paidBy)),
        },
        // 'error', JAMÁS 'splitAmongAll'. Repartir lo no seleccionado entre
        // TODOS producía una "media previa" (cada persona pagando 1/N de lo
        // que nadie ha cogido, SUMADO a lo suyo): el bug que este arreglo
        // erradica. sanitizeLine ya reasigna las líneas sin dueño al pagador,
        // así que aquí no debe quedar ninguna sin asignar; si quedara, es un
        // bug y preferimos que salte a que se promedie en silencio.
        unassignedPolicy: 'error',
        // Residual por unidades (P2.1): lo reclamado parcialmente también
        // recae en el pagador, unidad a unidad.
        payerId: paidBy,
      });
      contributions.push({
        paidBy,
        grandTotal: ticket.grandTotal,
        consumption,
      });

      // P5 conserva la deuda ORIGINAL por ticket. Una sesión puede seguir
      // teniendo nombres sin cuenta: solo se publican pares con dos UID
      // registrados, sin inventar identidad a partir del nombre.
      const payerUid = uidByPid.get(paidBy);
      if (payerUid) {
        const byDebtor = new Map<string, Cents>();
        for (const [pid, amount] of Object.entries(consumption)) {
          const debtorUid = uidByPid.get(pid);
          if (!debtorUid || debtorUid === payerUid || amount <= 0) continue;
          byDebtor.set(debtorUid, (byDebtor.get(debtorUid) ?? 0) + amount);
        }
        for (const [debtorUid, amount] of [...byDebtor.entries()]
          .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)) {
          economicEntries.push({
            id: `${account.id}_${ticket.id}_${encodedPair(debtorUid, payerUid)}`,
            memberUids: orderedUids(debtorUid, payerUid),
            debtorUid,
            creditorUid: payerUid,
            amount,
            currency,
            accountId: account.id,
            ticketId: ticket.id,
            ticketName: ticket.merchantName ?? account.name ?? ticket.id,
            ticketDate: ticket.date,
            spaceId: ticket.spaceId,
          });
        }
      }
    }
    accountTotals[account.id] = { grandTotal: accountTotal };
  }

  const frozen: FrozenSettlement[] = s.settlements
    .filter((st) => st.state === 'confirmed')
    .map((st) => ({ from: st.from, to: st.to, amount: st.amount }))
    .concat(s.externalConfirmed ?? []);

  const legacyPayments: LegacyPaymentDraft[] = [];
  for (const settlement of s.settlements) {
    // `pending` es una sugerencia de recompute, no un pago humano. Solo
    // `marked` (el deudor dice que pagó) y `confirmed` son movimientos.
    if (settlement.state === 'pending') continue;
    const payerUid = uidByPid.get(settlement.from);
    const receiverUid = uidByPid.get(settlement.to);
    if (!payerUid || !receiverUid || payerUid === receiverUid ||
        settlement.amount <= 0) continue;
    legacyPayments.push({
      id: `legacy_${settlement.id}`,
      memberUids: orderedUids(payerUid, receiverUid),
      payerUid,
      receiverUid,
      amount: settlement.amount,
      currency,
      status: settlement.state === 'confirmed' ? 'confirmed' : 'pending',
      settlementId: settlement.id,
    });
  }

  const balance = computeBalance({
    participantIds: activeIds,
    tickets: contributions,
    frozenSettlements: frozen,
  });

  // Sincronización de liquidaciones (idempotente y a prueba de carreras):
  // - Confirmadas: intocables (congeladas, RF-53).
  // - Objetivos con id determinista pending_{from}_{to}: si el doc existe
  //   con el MISMO importe, no se toca (preserva `marked`); si difiere o
  //   no existe, se (sobre)escribe como pending.
  // - Cualquier doc no confirmado que no corresponda a un objetivo se borra
  //   (incluye duplicados legacy con id aleatorio).
  const nonConfirmed = s.settlements.filter((st) => st.state !== 'confirmed');
  const writes: SettlementDraft[] = [];
  const untouched: string[] = [];
  for (const target of balance.settlements) {
    const id = settlementId(target);
    const existing = nonConfirmed.find((st) => st.id === id);
    if (existing && existing.amount === target.amount) {
      untouched.push(id);
    } else {
      writes.push(target);
    }
  }
  const targetIds = new Set(balance.settlements.map(settlementId));
  const removals = nonConfirmed
    .filter((st) => !targetIds.has(st.id))
    .map((st) => st.id);

  let grandTotal = 0;
  for (const t of Object.values(accountTotals)) grandTotal += t.grandTotal;
  let settledConfirmed = 0;
  let settledMarked = 0;
  for (const st of s.settlements) {
    if (st.state === 'confirmed') settledConfirmed += st.amount;
    if (st.state === 'marked' && untouched.includes(st.id)) {
      settledMarked += st.amount;
    }
  }
  settledConfirmed += (s.externalConfirmed ?? [])
    .reduce((sum, settlement) => sum + settlement.amount, 0);
  const settlementRequired =
    settledConfirmed +
    balance.settlements.reduce((total, st) => total + st.amount, 0);

  return {
    accountTotals,
    sessionTotals: {
      grandTotal,
      settlementRequired,
      settledConfirmed,
      settledMarked,
    },
    balances: balance.balances,
    pendingSettlements:
      balance.settlements.length -
      s.settlements.filter(
        (st) => st.state === 'marked' && untouched.includes(st.id),
      ).length,
    settlementSync: { writes, untouched, removals },
    economicEntries,
    legacyPayments,
  };
}

/**
 * Normaliza una línea de Firestore al modelo del motor y RESUELVE las líneas
 * sin dueño hacia el pagador:
 *  - `all`: elección explícita del anfitrión → se respeta tal cual.
 *  - con consumidores válidos: `one` (1 y venía como `one`) o `shared`.
 *  - sin consumidores (sin reclamar): la cubre `payerId` como `one`. Esto es
 *    lo que elimina la "media previa": lo que nadie ha cogido es de quien
 *    pagó (neto cero para él en esa parte), y se reduce a medida que la gente
 *    reclama sus productos.
 */
function sanitizeLine(
  line: LineDoc,
  known: ReadonlySet<string>,
  payerId: string,
): SplitLine {
  const rawType = line.assignment?.type ?? 'unassigned';
  const units = unitsFromQuantityMilli(line.quantityMilli ?? 1000);

  // P2.2 es opt-in por línea. La ausencia de schemaVersion conserva el
  // reparto histórico/P2.1 sin reinterpretarlo silenciosamente.
  if (line.assignment?.schemaVersion === 2 && rawType === 'units') {
    const unitConsumers: Record<string, string[]> = {};
    for (let unit = 0; unit < units; unit++) {
      const members = line.assignment?.units?.[`u${unit}`] ?? {};
      const consumers: string[] = [];
      for (const [pid, selected] of Object.entries(members)) {
        if (!selected) continue;
        if (known.has(pid)) consumers.push(pid);
        else {
          logger.warn('Consumidor de unidad desconocido; se ignora', {
            line: line.id,
            unit,
            pid,
          });
        }
      }
      if (consumers.length > 0) unitConsumers[String(unit)] = consumers;
    }
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      unitConsumers,
      // Ignorado por el motor cuando existe unitConsumers.
      assignment: { type: 'unassigned', weights: {} },
    };
  }

  if (rawType === 'all') {
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      assignment: { type: 'all', weights: {} },
    };
  }

  const weights: Record<string, number> = {};
  for (const [pid, weight] of Object.entries(
    line.assignment?.participants ?? {},
  )) {
    if (known.has(pid) && weight > 0) weights[pid] = weight;
    else if (!known.has(pid)) {
      logger.warn('Asignación a participante desconocido; se ignora', {
        line: line.id,
        pid,
      });
    }
  }

  const consumers = Object.keys(weights);
  if (consumers.length === 0) {
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      assignment: { type: 'one', weights: { [payerId]: 1 } },
    };
  }

  const type = consumers.length === 1 && rawType === 'one' ? 'one' : 'shared';
  return {
    id: line.id,
    totalPrice: line.totalPrice,
    units,
    assignment: { type, weights },
  };
}

// ── Lectura de Firestore y escritura de agregados ─────────────────────────

export async function recomputeSession(sid: string): Promise<void> {
  const db = getFirestore();
  const sessionRef = db.doc(`sessions/${sid}`);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return; // borrada: cleanup se encarga

  const [
    participantsSnap,
    accountsSnap,
    settlementsSnap,
    economicEntriesSnap,
    economicPaymentsSnap,
    externalPaymentsSnap,
  ] = await Promise.all([
    sessionRef.collection('participants').get(),
    sessionRef.collection('accounts').get(),
    sessionRef.collection('settlements').get(),
    db.collection('economicEntries').where('sessionId', '==', sid).get(),
    db.collection('economicPayments').where('sourceSessionId', '==', sid).get(),
    db.collection('economicPayments').where('sessionIds', 'array-contains', sid).get(),
  ]);

  const accounts: AccountDoc[] = await Promise.all(
    accountsSnap.docs.map(async (accountDoc) => {
      const ticketsSnap = await accountDoc.ref.collection('tickets').get();
      const tickets: TicketDoc[] = await Promise.all(
        ticketsSnap.docs.map(async (ticketDoc) => {
          const linesSnap = await ticketDoc.ref.collection('lines').get();
          return {
            id: ticketDoc.id,
            grandTotal: (ticketDoc.data().grandTotal as number) ?? 0,
            paidByParticipantId:
              (ticketDoc.data().paidByParticipantId as string) ?? '',
            splitModeOverride: ticketDoc.data().splitModeOverride as
              | SplitMode
              | undefined,
            merchantName:
              (ticketDoc.data().merchant as { name?: string } | undefined)
                ?.name,
            date: ticketDoc.data().date as string | undefined,
            spaceId: ticketDoc.data().spaceId as string | undefined,
            lines: linesSnap.docs.map((l) => ({
              id: l.id,
              totalPrice: (l.data().totalPrice as number) ?? 0,
              quantityMilli: l.data().quantityMilli as number | undefined,
              assignment: l.data().assignment,
            })),
          };
        }),
      );
      return {
        id: accountDoc.id,
        name: accountDoc.data().name as string | undefined,
        tickets,
      };
    }),
  );

  // `claimedByDevice` también identifica invitados anónimos. Solo se eleva
  // a identidad económica si existe un perfil público registrado con ese UID.
  const claimedUids = [
    ...new Set(
      participantsSnap.docs
        .map((p) => p.data().claimedByDevice as string | undefined)
        .filter((value): value is string => Boolean(value)),
    ),
  ];
  const claimedProfiles = claimedUids.length === 0
    ? []
    : await db.getAll(
      ...claimedUids.map((claimedUid) => db.doc(`profiles/${claimedUid}`)),
    );
  const registeredClaims = new Set(
    claimedProfiles.filter((profile) => profile.exists).map((profile) => profile.id),
  );
  const sessionOwnerUid = sessionSnap.data()?.ownerUid as string | undefined;
  const pidByUid = new Map<string, string>();
  for (const participant of participantsSnap.docs) {
    const data = participant.data();
    const claimed = data.claimedByDevice as string | undefined;
    const uid = data.isOwner === true
      ? sessionOwnerUid
      : claimed && registeredClaims.has(claimed)
      ? claimed
      : undefined;
    if (uid) pidByUid.set(uid, participant.id);
  }
  const currentEntryIds = new Set(economicEntriesSnap.docs.map((doc) => doc.id));
  const externalConfirmed: Array<{ from: string; to: string; amount: Cents }> = [];
  for (const payment of externalPaymentsSnap.docs) {
    const data = payment.data();
    if (data.source !== 'user' || data.status !== 'confirmed') continue;
    const from = pidByUid.get(data.payerUid as string);
    const to = pidByUid.get(data.receiverUid as string);
    if (!from || !to || from === to) continue;
    const allocations = data.allocations as Record<string, number> | undefined;
    const amount = Object.entries(allocations ?? {})
      .filter(([entryId]) => currentEntryIds.has(entryId))
      .reduce((sum, [, cents]) => sum + cents, 0);
    if (amount > 0) externalConfirmed.push({ from, to, amount });
  }

  const snapshot: SessionSnapshot = {
    splitModeDefault:
      (sessionSnap.data()?.splitModeDefault as SplitMode) ?? 'equal',
    ownerUid: sessionOwnerUid,
    currency: (sessionSnap.data()?.currency as string | undefined) ?? 'EUR',
    participants: participantsSnap.docs.map((p) => {
      const isOwner = p.data().isOwner as boolean | undefined;
      const claimed = p.data().claimedByDevice as string | undefined;
      return {
        id: p.id,
        isOwner,
        active: p.data().active as boolean | undefined,
        order: p.data().order as number | undefined,
        userUid: isOwner
          ? sessionOwnerUid
          : claimed && registeredClaims.has(claimed)
          ? claimed
          : undefined,
        claimedByDevice: claimed,
      };
    }),
    accounts,
    settlements: settlementsSnap.docs.map((st) => ({
      id: st.id,
      from: st.data().from as string,
      to: st.data().to as string,
      amount: st.data().amount as number,
      state: st.data().state as SettlementDoc['state'],
    })),
    externalConfirmed,
  };

  if (snapshot.participants.length === 0) return; // sesión a medio crear

  const result = computeAggregates(snapshot);

  const entryData = (entry: EconomicEntryDraft): Record<string, unknown> => ({
    memberUids: entry.memberUids,
    debtorUid: entry.debtorUid,
    creditorUid: entry.creditorUid,
    amount: entry.amount,
    currency: entry.currency,
    sessionId: sid,
    accountId: entry.accountId,
    ticketId: entry.ticketId,
    ticketName: entry.ticketName,
    ...(entry.ticketDate ? { ticketDate: entry.ticketDate } : {}),
    ...(entry.spaceId ? { spaceId: entry.spaceId } : {}),
    schemaVersion: 1,
  });
  const legacyPaymentData = (
    payment: LegacyPaymentDraft,
  ): Record<string, unknown> => ({
    memberUids: payment.memberUids,
    pairId: encodedPair(payment.payerUid, payment.receiverUid),
    payerUid: payment.payerUid,
    receiverUid: payment.receiverUid,
    amount: payment.amount,
    currency: payment.currency,
    status: payment.status,
    source: 'legacySettlement',
    sourceSessionId: sid,
    settlementId: payment.settlementId,
    schemaVersion: 1,
  });
  const desiredEntries = new Map(
    result.economicEntries.map((entry) => [
      `${sid}_${entry.id}`,
      entryData(entry),
    ]),
  );
  const desiredLegacyPayments = new Map(
    result.legacyPayments.map((payment) => [
      `${sid}_${payment.id}`,
      legacyPaymentData(payment),
    ]),
  );
  const comparable = (data: Record<string, unknown>): string => {
    const copy = { ...data };
    delete copy.createdAt;
    delete copy.updatedAt;
    delete copy.confirmedAt;
    return JSON.stringify(copy);
  };
  const economicEntriesUnchanged =
    economicEntriesSnap.size === desiredEntries.size &&
    economicEntriesSnap.docs.every((doc) => {
      const desired = desiredEntries.get(doc.id);
      return desired !== undefined &&
        comparable(doc.data()) === comparable(desired);
    });
  const legacyDocs = economicPaymentsSnap.docs.filter(
    (doc) => doc.data().source === 'legacySettlement',
  );
  const legacyPaymentsUnchanged =
    legacyDocs.length === desiredLegacyPayments.size &&
    legacyDocs.every((doc) => {
      const desired = desiredLegacyPayments.get(doc.id);
      return desired !== undefined &&
        comparable(doc.data()) === comparable(desired);
    });

  // ¿Cambió algo? Comparación con lo persistido para evitar escrituras
  // (y notificaciones/lecturas de listeners) innecesarias.
  const current = sessionSnap.data() ?? {};
  const unchanged =
    JSON.stringify(current.totals) === JSON.stringify(result.sessionTotals) &&
    JSON.stringify(current.balances) === JSON.stringify(result.balances) &&
    current.pendingSettlements === result.pendingSettlements &&
    result.settlementSync.writes.length === 0 &&
    result.settlementSync.removals.length === 0 &&
    economicEntriesUnchanged &&
    legacyPaymentsUnchanged &&
    accountsSnap.docs.every(
      (a) =>
        JSON.stringify(a.data().totals) ===
        JSON.stringify(result.accountTotals[a.id]),
    );
  if (unchanged) return;

  const batch = db.batch();
  for (const accountDoc of accountsSnap.docs) {
    batch.update(accountDoc.ref, {
      totals: result.accountTotals[accountDoc.id],
    });
  }
  batch.update(sessionRef, {
    totals: result.sessionTotals,
    balances: result.balances,
    pendingSettlements: result.pendingSettlements,
    participantsCount: snapshot.participants.length,
    computeVersion: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
  });
  for (const id of result.settlementSync.removals) {
    batch.delete(sessionRef.collection('settlements').doc(id));
  }
  for (const draft of result.settlementSync.writes) {
    // set() con id determinista: idempotente entre ejecuciones concurrentes.
    batch.set(sessionRef.collection('settlements').doc(settlementId(draft)), {
      from: draft.from,
      to: draft.to,
      amount: draft.amount,
      state: 'pending',
      stateHistory: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const doc of economicEntriesSnap.docs) {
    if (!desiredEntries.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredEntries) {
    const existing = economicEntriesSnap.docs.find((doc) => doc.id === id);
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(db.collection('economicEntries').doc(id), {
      ...data,
      createdAt: existing?.data().createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const doc of legacyDocs) {
    if (!desiredLegacyPayments.has(doc.id)) batch.delete(doc.ref);
  }
  for (const [id, data] of desiredLegacyPayments) {
    const existing = legacyDocs.find((doc) => doc.id === id);
    if (existing && comparable(existing.data()) === comparable(data)) continue;
    batch.set(db.collection('economicPayments').doc(id), {
      ...data,
      createdAt: existing?.data().createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(data.status === 'confirmed'
        ? { confirmedAt: FieldValue.serverTimestamp() }
        : {}),
    });
  }
  await batch.commit();
  logger.info('Sesión recalculada', {
    sid,
    grandTotal: result.sessionTotals.grandTotal,
    settlements: result.settlementSync,
  });
}

// ── Triggers (una "función" conceptual, tres bindings) ────────────────────

export const recomputeOnLine = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}/lines/{lid}',
  (event) => recomputeSession(event.params.sid),
);

export const recomputeOnTicket = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}',
  (event) => recomputeSession(event.params.sid),
);

export const recomputeOnParticipant = onDocumentWritten(
  'sessions/{sid}/participants/{pid}',
  (event) => recomputeSession(event.params.sid),
);

// Los cambios de estado de pago también actualizan agregados
// (settledConfirmed/Marked, pendientes) y regeneran lo que proceda.
// No hay bucle: recompute solo escribe cuando algo cambia, así que la
// ejecución disparada por sus propias escrituras converge y se detiene.
export const recomputeOnSettlement = onDocumentWritten(
  'sessions/{sid}/settlements/{stid}',
  (event) => recomputeSession(event.params.sid),
);

// Un pago P5 confirmado también debe congelarse en los balances legacy de
// sus sesiones. Así ambas vistas se derivan del mismo evento y no permiten
// volver a pagar desde el detalle antiguo de la cuenta.
export const recomputeOnEconomicPayment = onDocumentWritten(
  'economicPayments/{paymentId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status === after?.status) return;
    if (before?.status !== 'confirmed' && after?.status !== 'confirmed') return;
    const sessionIds = new Set<string>([
      ...((before?.sessionIds as string[] | undefined) ?? []),
      ...((after?.sessionIds as string[] | undefined) ?? []),
    ]);
    await Promise.all([...sessionIds].map(recomputeSession));
  },
);

/** Migración perezosa y reconstruible para sesiones creadas antes de P5. */
export const rebuildMyEconomicRelations = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  if (
    auth.token.email_verified !== true ||
    auth.token.firebase?.sign_in_provider === 'anonymous'
  ) {
    throw new HttpsError('permission-denied', 'VERIFIED_ACCOUNT_REQUIRED');
  }
  const uid = auth.uid;
  const db = getFirestore();
  const markerRef = db.doc(`users/${uid}`);
  const marker = await markerRef.get();
  if (marker.data()?.economicProjectionVersion === 1) {
    return { rebuilt: 0, version: 1 };
  }

  const [owned, claimed] = await Promise.all([
    db.collection('sessions').where('ownerUid', '==', uid).limit(201).get(),
    db.collectionGroup('participants')
      .where('claimedByDevice', '==', uid).limit(201).get(),
  ]);
  if (owned.size > 200 || claimed.size > 200) {
    throw new HttpsError('resource-exhausted', 'ECONOMIC_REBUILD_TOO_LARGE');
  }
  const sessionIds = new Set(owned.docs.map((doc) => doc.id));
  for (const participant of claimed.docs) {
    const session = participant.ref.parent.parent;
    if (session) sessionIds.add(session.id);
  }
  // Secuencial: evita picos de lecturas/CPU y respeta el techo de coste.
  for (const sid of [...sessionIds].sort()) await recomputeSession(sid);
  await markerRef.set({
    economicProjectionVersion: 1,
    economicProjectionUpdatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { rebuilt: sessionIds.size, version: 1 };
});
