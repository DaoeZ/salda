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
  type SplitLine,
  type SplitMode,
} from './domain/splitEngine.js';

// ── Modelo en memoria (independiente de Firestore para poder testearlo) ──

export interface ParticipantDoc {
  id: string;
  isOwner?: boolean;
  active?: boolean;
  order?: number;
}

export interface LineDoc {
  id: string;
  totalPrice: Cents;
  assignment?: {
    type?: string;
    participants?: Record<string, number>;
  };
}

export interface TicketDoc {
  id: string;
  grandTotal: Cents;
  paidByParticipantId: string;
  splitModeOverride?: SplitMode;
  lines: LineDoc[];
}

export interface AccountDoc {
  id: string;
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
  participants: ParticipantDoc[];
  accounts: AccountDoc[];
  settlements: SettlementDoc[];
}

export interface RecomputeResult {
  accountTotals: Record<string, { grandTotal: Cents }>;
  sessionTotals: {
    grandTotal: Cents;
    settledConfirmed: Cents;
    settledMarked: Cents;
  };
  balances: Record<string, ParticipantBalance>;
  pendingSettlements: number;
  settlementOps: {
    /** ids existentes que se conservan (marked/pending coincidentes + confirmadas). */
    keep: string[];
    create: SettlementDraft[];
    remove: string[];
  };
}

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

  const accountTotals: RecomputeResult['accountTotals'] = {};
  const contributions: TicketContribution[] = [];

  for (const account of s.accounts) {
    let accountTotal = 0;
    for (const ticket of account.tickets) {
      accountTotal += ticket.grandTotal;
      const mode = ticket.splitModeOverride ?? s.splitModeDefault;
      const consumption = splitTicket({
        participantIds: activeIds,
        mode,
        ticket: {
          grandTotal: ticket.grandTotal,
          lines: ticket.lines.map((l) => sanitizeLine(l, known)),
        },
        // Para agregados, las líneas sin asignar se reparten entre todos
        // (RF-46); la UI avisa aparte de que existen huérfanas.
        unassignedPolicy: 'splitAmongAll',
      });
      let paidBy = ticket.paidByParticipantId;
      if (!known.has(paidBy)) {
        logger.warn('Pagador desconocido; se reasigna al owner', {
          ticket: ticket.id,
          paidBy,
        });
        paidBy = fallbackPayer;
      }
      contributions.push({
        paidBy,
        grandTotal: ticket.grandTotal,
        consumption,
      });
    }
    accountTotals[account.id] = { grandTotal: accountTotal };
  }

  const frozen: FrozenSettlement[] = s.settlements
    .filter((st) => st.state === 'confirmed')
    .map((st) => ({ from: st.from, to: st.to, amount: st.amount }));

  const balance = computeBalance({
    participantIds: activeIds,
    tickets: contributions,
    frozenSettlements: frozen,
  });

  // Sincronización de liquidaciones: las confirmadas son intocables; las
  // pending/marked existentes se conservan si (from,to,amount) coincide con
  // el objetivo (preserva el estado "marked"); el resto se borra/crea.
  const existing = s.settlements.filter((st) => st.state !== 'confirmed');
  const keep: string[] = s.settlements
    .filter((st) => st.state === 'confirmed')
    .map((st) => st.id);
  const create: SettlementDraft[] = [];
  const used = new Set<string>();
  for (const target of balance.settlements) {
    const match = existing.find(
      (st) =>
        !used.has(st.id) &&
        st.from === target.from &&
        st.to === target.to &&
        st.amount === target.amount,
    );
    if (match) {
      used.add(match.id);
      keep.push(match.id);
    } else {
      create.push(target);
    }
  }
  const remove = existing.filter((st) => !used.has(st.id)).map((st) => st.id);

  let grandTotal = 0;
  for (const t of Object.values(accountTotals)) grandTotal += t.grandTotal;
  let settledConfirmed = 0;
  let settledMarked = 0;
  for (const st of s.settlements) {
    if (st.state === 'confirmed') settledConfirmed += st.amount;
    if (st.state === 'marked' && keep.includes(st.id)) {
      settledMarked += st.amount;
    }
  }

  return {
    accountTotals,
    sessionTotals: { grandTotal, settledConfirmed, settledMarked },
    balances: balance.balances,
    pendingSettlements:
      balance.settlements.length -
      s.settlements.filter(
        (st) => st.state === 'marked' && keep.includes(st.id),
      ).length,
    settlementOps: { keep, create, remove },
  };
}

function sanitizeLine(line: LineDoc, known: ReadonlySet<string>): SplitLine {
  const rawType = line.assignment?.type ?? 'unassigned';
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
  const type =
    rawType === 'all'
      ? 'all'
      : Object.keys(weights).length === 0
        ? 'unassigned'
        : Object.keys(weights).length === 1 && rawType === 'one'
          ? 'one'
          : 'shared';
  return {
    id: line.id,
    totalPrice: line.totalPrice,
    assignment: { type, weights },
  };
}

// ── Lectura de Firestore y escritura de agregados ─────────────────────────

export async function recomputeSession(sid: string): Promise<void> {
  const db = getFirestore();
  const sessionRef = db.doc(`sessions/${sid}`);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return; // borrada: cleanup se encarga

  const [participantsSnap, accountsSnap, settlementsSnap] = await Promise.all([
    sessionRef.collection('participants').get(),
    sessionRef.collection('accounts').get(),
    sessionRef.collection('settlements').get(),
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
            lines: linesSnap.docs.map((l) => ({
              id: l.id,
              totalPrice: (l.data().totalPrice as number) ?? 0,
              assignment: l.data().assignment,
            })),
          };
        }),
      );
      return { id: accountDoc.id, tickets };
    }),
  );

  const snapshot: SessionSnapshot = {
    splitModeDefault:
      (sessionSnap.data()?.splitModeDefault as SplitMode) ?? 'equal',
    participants: participantsSnap.docs.map((p) => ({
      id: p.id,
      isOwner: p.data().isOwner as boolean | undefined,
      active: p.data().active as boolean | undefined,
      order: p.data().order as number | undefined,
    })),
    accounts,
    settlements: settlementsSnap.docs.map((st) => ({
      id: st.id,
      from: st.data().from as string,
      to: st.data().to as string,
      amount: st.data().amount as number,
      state: st.data().state as SettlementDoc['state'],
    })),
  };

  if (snapshot.participants.length === 0) return; // sesión a medio crear

  const result = computeAggregates(snapshot);

  // ¿Cambió algo? Comparación con lo persistido para evitar escrituras
  // (y notificaciones/lecturas de listeners) innecesarias.
  const current = sessionSnap.data() ?? {};
  const unchanged =
    JSON.stringify(current.totals) === JSON.stringify(result.sessionTotals) &&
    JSON.stringify(current.balances) === JSON.stringify(result.balances) &&
    result.settlementOps.create.length === 0 &&
    result.settlementOps.remove.length === 0 &&
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
  for (const id of result.settlementOps.remove) {
    batch.delete(sessionRef.collection('settlements').doc(id));
  }
  for (const draft of result.settlementOps.create) {
    batch.set(sessionRef.collection('settlements').doc(), {
      from: draft.from,
      to: draft.to,
      amount: draft.amount,
      state: 'pending',
      stateHistory: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  logger.info('Sesión recalculada', {
    sid,
    grandTotal: result.sessionTotals.grandTotal,
    settlements: result.settlementOps,
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
