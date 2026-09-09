import { createHash } from 'node:crypto';

import {
  FieldValue,
  Timestamp,
  getFirestore,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { manualIdOf } from './domain/economicActor.js';
import {
  economicActingRole,
  type EconomicActingRole,
} from './domain/economicAuthority.js';
import {
  computeEconomicLedger,
  type BilateralEconomicBalance,
  type EconomicObligation,
  type EconomicPaymentRecord,
} from './domain/economicLedger.js';

const idempotencyPattern = /^[A-Za-z0-9_-]{16,80}$/;
const paymentIdPattern = /^[A-Za-z0-9_-]{1,500}$/;
const entryIdPattern = /^[A-Za-z0-9_-]{1,400}$/;

/** Techo por llamada: una liquidación múltiple es cómoda, no masiva. */
const maxEntriesPerSettlement = 25;

const orderedUids = (left: string, right: string): [string, string] =>
  left < right ? [left, right] : [right, left];

export const economicPairId = (left: string, right: string): string =>
  createHash('sha256')
    .update(orderedUids(left, right).join('\0'), 'utf8')
    .digest('hex');

export interface CreatePaymentInput {
  receiverUid: string;
  amount: number;
  currency: string;
  idempotencyKey: string;
}

type ResolveAction = 'confirm' | 'cancel' | 'reject';

/**
 * [authority] permite que quien representa a una identidad SIN cuenta
 * (ADR-038) resuelva por ella. Sin él se compara el UID directamente, que es
 * el caso normal entre dos cuentas: nadie más que el receptor confirma.
 */
export function resolvePaymentTransition(
  payment: Record<string, unknown>,
  actorUid: string,
  action: ResolveAction,
  authority: {
    receiverRole?: EconomicActingRole;
    payerRole?: EconomicActingRole;
  } = {},
): 'confirmed' | 'cancelled' {
  if (payment.source !== 'user') {
    throw new HttpsError('failed-precondition', 'LEGACY_PAYMENT_READ_ONLY');
  }
  const target = action === 'confirm' ? 'confirmed' : 'cancelled';
  if (payment.status === target) return target;
  if (payment.status !== 'pending') {
    throw new HttpsError('failed-precondition', 'PAYMENT_ALREADY_RESOLVED');
  }
  const receiverRole = authority.receiverRole ??
    (payment.receiverUid === actorUid ? 'self' : 'none');
  const payerRole = authority.payerRole ??
    (payment.payerUid === actorUid ? 'self' : 'none');
  if (
    ((action === 'confirm' || action === 'reject') && receiverRole === 'none') ||
    (action === 'cancel' && payerRole === 'none')
  ) {
    throw new HttpsError('permission-denied', 'PAYMENT_ACTOR_INVALID');
  }
  return target;
}

export function validateCreatePaymentInput(raw: unknown): CreatePaymentInput {
  if (!raw || typeof raw !== 'object') {
    throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
  }
  const data = raw as Record<string, unknown>;
  const receiverUid = data.receiverUid;
  const amount = data.amount;
  const currency = data.currency;
  const idempotencyKey = data.idempotencyKey;
  if (
    typeof receiverUid !== 'string' ||
    receiverUid.length < 1 ||
    receiverUid.length > 128 ||
    !Number.isSafeInteger(amount) ||
    (amount as number) <= 0 ||
    (amount as number) > 1_000_000_000 ||
    typeof currency !== 'string' ||
    !/^[A-Z]{3}$/.test(currency) ||
    typeof idempotencyKey !== 'string' ||
    !idempotencyPattern.test(idempotencyKey)
  ) {
    throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
  }
  return {
    receiverUid,
    amount: amount as number,
    currency,
    idempotencyKey,
  };
}

/** Saldo todavía pagable, descontando pagos pendientes de esa dirección. */
export function availablePaymentAmount(
  balance: BilateralEconomicBalance,
  payerUid: string,
  receiverUid: string,
): number {
  const signed = balance.signedOutstanding;
  const debtor = signed > 0 ? balance.firstUid : signed < 0
    ? balance.secondUid : undefined;
  const creditor = signed > 0 ? balance.secondUid : signed < 0
    ? balance.firstUid : undefined;
  if (debtor !== payerUid || creditor !== receiverUid) return 0;
  const reserved = payerUid === balance.firstUid
    ? balance.pendingFirstToSecond
    : balance.pendingSecondToFirst;
  return Math.max(0, Math.abs(signed) - reserved);
}

export function allocatePaymentToEntries(
  amount: number,
  entries: Array<{ id: string; amount: number }>,
  reservedByEntry: ReadonlyMap<string, number> = new Map(),
): Record<string, number> {
  let left = amount;
  const allocations: Record<string, number> = {};
  for (const entry of [...entries].sort((a, b) => a.id.localeCompare(b.id))) {
    if (left === 0) break;
    const remaining = Math.max(
      0,
      entry.amount - (reservedByEntry.get(entry.id) ?? 0),
    );
    const allocated = Math.min(left, remaining);
    if (allocated > 0) allocations[entry.id] = allocated;
    left -= allocated;
  }
  if (left !== 0) {
    throw new HttpsError('aborted', 'PAYMENT_ALLOCATION_CONFLICT');
  }
  return allocations;
}

// ── Liquidación POR OBLIGACIÓN (ADR-038) ──────────────────────────────────
// Un saldo agregado ("Test te debe 14,73") es un RESUMEN, nunca una nueva
// obligación. Se liquida cada deuda contra su ticket de origen, así que un
// pago siempre nace atado a una entrada de `economicEntries` y conserva su
// trazabilidad. Confirmar varias a la vez es una comodidad de la interfaz:
// económicamente siguen siendo N liquidaciones independientes.

export interface SettleEntryRequest {
  entryId: string;
  /** Ausente = el pendiente completo de ESA obligación (el caso normal). */
  amount?: number;
}

export interface SettleEntriesInput {
  entries: SettleEntryRequest[];
  idempotencyKey: string;
}

/** Obligación ya resuelta contra Firestore, lista para decidir sobre ella. */
export interface EntrySettlementContext {
  id: string;
  debtorUid: string;
  creditorUid: string;
  amount: number;
  currency: string;
  memberUids: string[];
  sessionId: string;
  spaceId?: string;
  /** Céntimos ya asignados por pagos NO cancelados (pendientes incluidos). */
  allocated: number;
  /** Título con el que el actor puede obrar por el acreedor y por el deudor. */
  creditorRole: EconomicActingRole;
  debtorRole: EconomicActingRole;
}

export interface SettlementDraft {
  paymentId: string;
  entryId: string;
  payerUid: string;
  receiverUid: string;
  amount: number;
  currency: string;
  status: 'pending' | 'confirmed';
  memberUids: string[];
  sessionId: string;
  spaceId?: string;
  /** Identidad sin cuenta representada, cuando la acción es en su nombre. */
  onBehalfOfManualId?: string;
}

export function validateSettleEntriesInput(raw: unknown): SettleEntriesInput {
  if (!raw || typeof raw !== 'object') {
    throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
  }
  const data = raw as Record<string, unknown>;
  const entries = data.entries;
  const idempotencyKey = data.idempotencyKey;
  if (
    !Array.isArray(entries) ||
    entries.length === 0 ||
    entries.length > maxEntriesPerSettlement ||
    typeof idempotencyKey !== 'string' ||
    !idempotencyPattern.test(idempotencyKey)
  ) {
    throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
  }
  const seen = new Set<string>();
  const parsed: SettleEntryRequest[] = entries.map((raw) => {
    const entry = raw as Record<string, unknown>;
    const entryId = entry?.entryId;
    const amount = entry?.amount;
    if (
      typeof entryId !== 'string' ||
      !entryIdPattern.test(entryId) ||
      seen.has(entryId) ||
      (amount !== undefined &&
        amount !== null &&
        (!Number.isSafeInteger(amount) ||
          (amount as number) <= 0 ||
          (amount as number) > 1_000_000_000))
    ) {
      throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
    }
    seen.add(entryId);
    return {
      entryId,
      ...(amount === undefined || amount === null
        ? {}
        : { amount: amount as number }),
    };
  });
  return { entries: parsed, idempotencyKey };
}

const directionKey = (
  currency: string,
  payerUid: string,
  receiverUid: string,
): string => `${currency}\0${payerUid}\0${receiverUid}`;

/**
 * Decide qué liquidaciones se escriben, o falla sin escribir ninguna.
 *
 * Invariantes que impone (y por los que existe como función pura):
 *
 * 1. quien COBRA confirma; el deudor solo puede DECLARAR («ya he pagado»),
 *    que sigue siendo opcional y nunca es requisito para lo primero;
 * 2. nunca se paga más de lo que queda vivo en esa obligación concreta;
 * 3. nunca se paga más de lo que queda vivo en el saldo bilateral, que es lo
 *    que impide cobrar dos veces una deuda ya saldada por otra vía (una
 *    liquidación de sesión, que no deja asignación por ticket);
 * 4. o se escriben todas las liquidaciones pedidas, o ninguna.
 */
export function planEntrySettlements(params: {
  requests: SettleEntryRequest[];
  contexts: ReadonlyMap<string, EntrySettlementContext>;
  /** Disponible bilateral por dirección deudor→acreedor y moneda. */
  availableByDirection: ReadonlyMap<string, number>;
  idempotencyKey: string;
}): SettlementDraft[] {
  const drafts: SettlementDraft[] = [];
  const usedByDirection = new Map<string, number>();

  for (const request of params.requests) {
    const entry = params.contexts.get(request.entryId);
    if (!entry) throw new HttpsError('not-found', 'ENTRY_NOT_FOUND');

    // El acreedor manda: si el actor puede obrar por él, confirma. Solo si no
    // puede se mira el lado deudor, y entonces la acción es una declaración.
    const asCreditor = entry.creditorRole !== 'none';
    const asDebtor = entry.debtorRole !== 'none';
    if (!asCreditor && !asDebtor) {
      throw new HttpsError('permission-denied', 'PAYMENT_ACTOR_INVALID');
    }
    const role = asCreditor ? entry.creditorRole : entry.debtorRole;
    const representedActor = asCreditor ? entry.creditorUid : entry.debtorUid;

    const remaining = entry.amount - entry.allocated;
    if (remaining <= 0) {
      throw new HttpsError('failed-precondition', 'ENTRY_ALREADY_SETTLED');
    }
    const amount = request.amount ?? remaining;
    if (amount > remaining) {
      throw new HttpsError('failed-precondition', 'PAYMENT_EXCEEDS_BALANCE', {
        available: remaining,
      });
    }

    const key = directionKey(
      entry.currency,
      entry.debtorUid,
      entry.creditorUid,
    );
    const used = (usedByDirection.get(key) ?? 0) + amount;
    if (used > (params.availableByDirection.get(key) ?? 0)) {
      throw new HttpsError('failed-precondition', 'PAYMENT_EXCEEDS_BALANCE', {
        available: Math.max(0, params.availableByDirection.get(key) ?? 0),
      });
    }
    usedByDirection.set(key, used);

    const onBehalfOfManualId = role === 'representative'
      ? manualIdOf(representedActor)
      : undefined;
    drafts.push({
      paymentId: `settle_${entry.id}_${params.idempotencyKey}`,
      entryId: entry.id,
      payerUid: entry.debtorUid,
      receiverUid: entry.creditorUid,
      amount,
      currency: entry.currency,
      status: asCreditor ? 'confirmed' : 'pending',
      memberUids: entry.memberUids,
      sessionId: entry.sessionId,
      ...(entry.spaceId ? { spaceId: entry.spaceId } : {}),
      ...(onBehalfOfManualId ? { onBehalfOfManualId } : {}),
    });
  }
  return drafts;
}

function requireFullAccount(auth: Parameters<Parameters<typeof onCall>[0]>[0]['auth']) {
  if (!auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  if (
    auth.token.email_verified !== true ||
    auth.token.firebase?.sign_in_provider === 'anonymous'
  ) {
    throw new HttpsError('permission-denied', 'VERIFIED_ACCOUNT_REQUIRED');
  }
  return auth.uid;
}

export const createEconomicPayment = onCall(async (request) => {
  const payerUid = requireFullAccount(request.auth);
  const input = validateCreatePaymentInput(request.data);
  if (payerUid === input.receiverUid) {
    throw new HttpsError('invalid-argument', 'SELF_PAYMENT');
  }

  const db = getFirestore();
  const pairId = economicPairId(payerUid, input.receiverUid);
  const paymentId = `user_${pairId}_${input.idempotencyKey}`;
  const paymentRef = db.collection('economicPayments').doc(paymentId);
  const memberUids = orderedUids(payerUid, input.receiverUid);

  const result = await db.runTransaction(async (transaction) => {
    const [existing, payerProfile, receiverProfile, entries, payments] =
      await Promise.all([
        transaction.get(paymentRef),
        transaction.get(db.doc(`profiles/${payerUid}`)),
        transaction.get(db.doc(`profiles/${input.receiverUid}`)),
        transaction.get(
          db.collection('economicEntries')
            .where('memberUids', 'array-contains', payerUid),
        ),
        transaction.get(
          db.collection('economicPayments')
            .where('memberUids', 'array-contains', payerUid),
        ),
      ]);
    if (existing.exists) {
      return { paymentId, status: existing.data()?.status as string };
    }
    if (!payerProfile.exists || !receiverProfile.exists) {
      throw new HttpsError('failed-precondition', 'PROFILE_REQUIRED');
    }

    const obligations: EconomicObligation[] = entries.docs
      .map((doc) => ({ id: doc.id, data: doc.data() }))
      .filter((entry) =>
        entry.data.currency === input.currency &&
        entry.data.memberUids?.includes(input.receiverUid))
      .map((entry) => ({
        id: entry.id,
        debtorUid: entry.data.debtorUid as string,
        creditorUid: entry.data.creditorUid as string,
        amount: entry.data.amount as number,
        currency: entry.data.currency as string,
      }));
    const paymentRecords: EconomicPaymentRecord[] = payments.docs
      .map((doc) => ({ id: doc.id, data: doc.data() }))
      .filter((payment) =>
        payment.data.currency === input.currency &&
        payment.data.memberUids?.includes(input.receiverUid) &&
        ['pending', 'confirmed', 'cancelled'].includes(payment.data.status))
      .map((payment) => ({
        id: payment.id,
        payerUid: payment.data.payerUid as string,
        receiverUid: payment.data.receiverUid as string,
        amount: payment.data.amount as number,
        currency: payment.data.currency as string,
        status: payment.data.status as EconomicPaymentRecord['status'],
      }));
    const balance = computeEconomicLedger({
      obligations,
      payments: paymentRecords,
    }).find((candidate) =>
      candidate.currency === input.currency &&
      candidate.firstUid === memberUids[0] &&
      candidate.secondUid === memberUids[1]);
    const available = balance
      ? availablePaymentAmount(balance, payerUid, input.receiverUid)
      : 0;
    if (input.amount > available) {
      throw new HttpsError('failed-precondition', 'PAYMENT_EXCEEDS_BALANCE', {
        available,
      });
    }

    // Traza el pago hasta tickets concretos sin reescribirlos. La asignación
    // es FIFO determinista por id y queda congelada con el evento humano.
    const reservedByEntry = new Map<string, number>();
    for (const payment of payments.docs) {
      if (payment.data().status === 'cancelled') continue;
      const allocations = payment.data().allocations as
        | Record<string, number>
        | undefined;
      for (const [entryId, allocated] of Object.entries(allocations ?? {})) {
        reservedByEntry.set(
          entryId,
          (reservedByEntry.get(entryId) ?? 0) + allocated,
        );
      }
    }
    const candidates = entries.docs
      .filter((entry) =>
        entry.data().currency === input.currency &&
        entry.data().debtorUid === payerUid &&
        entry.data().creditorUid === input.receiverUid)
      .map((entry) => ({
        id: entry.id,
        amount: entry.data().amount as number,
        sessionId: entry.data().sessionId as string,
      }));
    const allocations = allocatePaymentToEntries(
      input.amount,
      candidates,
      reservedByEntry,
    );
    const sessionsByEntry = new Map(
      candidates.map((entry) => [entry.id, entry.sessionId]),
    );
    const sessionIds = [
      ...new Set(
        Object.keys(allocations)
          .map((entryId) => sessionsByEntry.get(entryId))
          .filter((sessionId): sessionId is string => Boolean(sessionId)),
      ),
    ].sort();

    transaction.create(paymentRef, {
      memberUids,
      pairId,
      payerUid,
      receiverUid: input.receiverUid,
      amount: input.amount,
      currency: input.currency,
      status: 'pending',
      source: 'user',
      createdByUid: payerUid,
      idempotencyKey: input.idempotencyKey,
      allocations,
      sessionIds,
      stateHistory: [
        { status: 'pending', at: Timestamp.now(), byUid: payerUid },
      ],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      schemaVersion: 1,
    });
    return { paymentId, status: 'pending' };
  });
  return result;
});

/**
 * Liquida obligaciones CONCRETAS: el receptor confirma que ha recibido el
 * dinero (total o parcialmente) sin necesitar que el deudor haya declarado
 * nada antes, o el deudor declara que ya pagó esa deuda.
 *
 * Cada obligación produce SU liquidación: confirmar dos de golpe no las funde
 * en un importe único, así que ninguna pierde el ticket que la explica.
 */
export const settleEconomicEntries = onCall(async (request) => {
  const actorUid = requireFullAccount(request.auth);
  const input = validateSettleEntriesInput(request.data);
  const db = getFirestore();

  return db.runTransaction(async (transaction) => {
    const entrySnaps = await transaction.getAll(
      ...input.entries.map((entry) =>
        db.collection('economicEntries').doc(entry.entryId)),
    );

    // Autoridad sobre los espacios implicados y vinculación de los manuales:
    // ambas cosas se leen del servidor, nunca del cliente.
    const spaceIds = new Set<string>();
    const manualsBySpace = new Map<string, Set<string>>();
    for (const snapshot of entrySnaps) {
      const data = snapshot.data();
      const spaceId = data?.spaceId as string | undefined;
      if (!spaceId) continue;
      spaceIds.add(spaceId);
      for (const actor of [data?.debtorUid, data?.creditorUid]) {
        const manualId = typeof actor === 'string'
          ? manualIdOf(actor)
          : undefined;
        if (!manualId) continue;
        const manuals = manualsBySpace.get(spaceId) ?? new Set<string>();
        manuals.add(manualId);
        manualsBySpace.set(spaceId, manuals);
      }
    }
    const adminBySpace = new Map<string, boolean>();
    for (const spaceId of spaceIds) {
      const [space, membership] = await Promise.all([
        transaction.get(db.doc(`spaces/${spaceId}`)),
        transaction.get(db.doc(`spaces/${spaceId}/members/${actorUid}`)),
      ]);
      adminBySpace.set(
        spaceId,
        space.data()?.ownerUid === actorUid ||
          membership.data()?.role === 'admin',
      );
    }
    const linkedByManual = new Map<string, string | undefined>();
    for (const [spaceId, manuals] of manualsBySpace) {
      for (const manualId of manuals) {
        const snapshot = await transaction.get(
          db.doc(`spaces/${spaceId}/manualParticipants/${manualId}`),
        );
        linkedByManual.set(
          `${spaceId}\0${manualId}`,
          (snapshot.data()?.linkedUid as string | undefined) ?? undefined,
        );
      }
    }

    // Saldo bilateral vivo: lo que ya se saldó por otra vía (una liquidación
    // de sesión) no deja asignación por ticket, así que sin este techo una
    // deuda podría cobrarse dos veces.
    const pivots = new Set<string>();
    for (const snapshot of entrySnaps) {
      for (const uid of (snapshot.data()?.memberUids as string[]) ?? []) {
        pivots.add(uid);
      }
    }
    const obligations: EconomicObligation[] = [];
    const paymentRecords: EconomicPaymentRecord[] = [];
    const allocatedByEntry = new Map<string, number>();
    const seenEntry = new Set<string>();
    const seenPayment = new Set<string>();
    for (const pivot of pivots) {
      const [entries, payments] = await Promise.all([
        transaction.get(
          db.collection('economicEntries')
            .where('memberUids', 'array-contains', pivot),
        ),
        transaction.get(
          db.collection('economicPayments')
            .where('memberUids', 'array-contains', pivot),
        ),
      ]);
      for (const doc of entries.docs) {
        if (seenEntry.has(doc.id)) continue;
        seenEntry.add(doc.id);
        const data = doc.data();
        obligations.push({
          id: doc.id,
          debtorUid: data.debtorUid as string,
          creditorUid: data.creditorUid as string,
          amount: data.amount as number,
          currency: (data.currency as string) ?? 'EUR',
        });
      }
      for (const doc of payments.docs) {
        if (seenPayment.has(doc.id)) continue;
        seenPayment.add(doc.id);
        const data = doc.data();
        const status = data.status as EconomicPaymentRecord['status'];
        paymentRecords.push({
          id: doc.id,
          payerUid: data.payerUid as string,
          receiverUid: data.receiverUid as string,
          amount: data.amount as number,
          currency: (data.currency as string) ?? 'EUR',
          status,
        });
        if (status === 'cancelled') continue;
        for (const [entryId, allocated] of Object.entries(
          (data.allocations as Record<string, number> | undefined) ?? {},
        )) {
          allocatedByEntry.set(
            entryId,
            (allocatedByEntry.get(entryId) ?? 0) + allocated,
          );
        }
      }
    }
    const balances = computeEconomicLedger({
      obligations,
      payments: paymentRecords,
    });

    const contexts = new Map<string, EntrySettlementContext>();
    const availableByDirection = new Map<string, number>();
    for (const snapshot of entrySnaps) {
      if (!snapshot.exists) throw new HttpsError('not-found', 'ENTRY_NOT_FOUND');
      const data = snapshot.data()!;
      const debtorUid = data.debtorUid as string;
      const creditorUid = data.creditorUid as string;
      const currency = (data.currency as string) ?? 'EUR';
      const spaceId = data.spaceId as string | undefined;
      const isAdmin = spaceId ? adminBySpace.get(spaceId) === true : false;
      const linkedOf = (actor: string): string | undefined => {
        const manualId = manualIdOf(actor);
        return manualId && spaceId
          ? linkedByManual.get(`${spaceId}\0${manualId}`)
          : undefined;
      };
      contexts.set(snapshot.id, {
        id: snapshot.id,
        debtorUid,
        creditorUid,
        amount: data.amount as number,
        currency,
        memberUids: (data.memberUids as string[]) ?? [],
        sessionId: data.sessionId as string,
        ...(spaceId ? { spaceId } : {}),
        allocated: allocatedByEntry.get(snapshot.id) ?? 0,
        creditorRole: economicActingRole({
          actor: creditorUid,
          viewerUid: actorUid,
          viewerIsSpaceAdmin: isAdmin,
          linkedUid: linkedOf(creditorUid),
        }),
        debtorRole: economicActingRole({
          actor: debtorUid,
          viewerUid: actorUid,
          viewerIsSpaceAdmin: isAdmin,
          linkedUid: linkedOf(debtorUid),
        }),
      });
      const key = directionKey(currency, debtorUid, creditorUid);
      if (!availableByDirection.has(key)) {
        const [first, second] = orderedUids(debtorUid, creditorUid);
        const balance = balances.find((candidate) =>
          candidate.currency === currency &&
          candidate.firstUid === first &&
          candidate.secondUid === second);
        availableByDirection.set(
          key,
          balance
            ? availablePaymentAmount(balance, debtorUid, creditorUid)
            : 0,
        );
      }
    }

    const drafts = planEntrySettlements({
      requests: input.entries,
      contexts,
      availableByDirection,
      idempotencyKey: input.idempotencyKey,
    });

    // Idempotencia: repetir la llamada con la misma clave no vuelve a cobrar.
    // Las lecturas van TODAS antes de la primera escritura (Firestore lo
    // exige dentro de una transacción).
    const existingDrafts = await transaction.getAll(
      ...drafts.map((draft) =>
        db.collection('economicPayments').doc(draft.paymentId)),
    );
    const alreadyWritten = new Map(
      existingDrafts
        .filter((snapshot) => snapshot.exists)
        .map((snapshot) => [snapshot.id, snapshot.data()?.status as string]),
    );

    const results: Array<{ paymentId: string; status: string }> = [];
    for (const draft of drafts) {
      const ref = db.collection('economicPayments').doc(draft.paymentId);
      const written = alreadyWritten.get(draft.paymentId);
      if (written !== undefined) {
        results.push({ paymentId: draft.paymentId, status: written });
        continue;
      }
      const now = Timestamp.now();
      transaction.create(ref, {
        memberUids: draft.memberUids,
        pairId: economicPairId(draft.payerUid, draft.receiverUid),
        payerUid: draft.payerUid,
        receiverUid: draft.receiverUid,
        amount: draft.amount,
        currency: draft.currency,
        status: draft.status,
        source: 'user',
        createdByUid: actorUid,
        idempotencyKey: input.idempotencyKey,
        // La obligación de origen viaja en el documento: un pago SIEMPRE se
        // puede explicar contra su ticket.
        economicEntryId: draft.entryId,
        allocations: { [draft.entryId]: draft.amount },
        sessionIds: [draft.sessionId],
        ...(draft.spaceId ? { spaceId: draft.spaceId } : {}),
        // Derivado e inmutable, igual que en la obligación: es lo que hace
        // demostrable la consulta de quien representa (ADR-038).
        hasManualParty: manualIdOf(draft.payerUid) !== undefined ||
          manualIdOf(draft.receiverUid) !== undefined,
        ...(draft.onBehalfOfManualId
          ? { onBehalfOfManualId: draft.onBehalfOfManualId }
          : {}),
        stateHistory: [{ status: draft.status, at: now, byUid: actorUid }],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        ...(draft.status === 'confirmed'
          ? { confirmedAt: FieldValue.serverTimestamp() }
          : {}),
        schemaVersion: 1,
      });
      results.push({ paymentId: draft.paymentId, status: draft.status });
    }
    return { payments: results };
  });
});

/**
 * Título con el que [actorUid] puede resolver un pago concreto.
 *
 * Solo consulta el espacio cuando hay una identidad SIN cuenta implicada:
 * entre dos cuentas la respuesta es la comparación de UID de siempre y no
 * cuesta ninguna lectura.
 */
async function actingAuthorityOn(
  db: Firestore,
  transaction: Transaction,
  payment: Record<string, unknown>,
  actorUid: string,
): Promise<{ receiverRole: EconomicActingRole; payerRole: EconomicActingRole }> {
  const receiverUid = payment.receiverUid as string;
  const payerUid = payment.payerUid as string;
  const spaceId = payment.spaceId as string | undefined;
  const manualActors = [receiverUid, payerUid].filter((actor) =>
    manualIdOf(actor) !== undefined);
  if (manualActors.length === 0 || !spaceId) {
    return {
      receiverRole: receiverUid === actorUid ? 'self' : 'none',
      payerRole: payerUid === actorUid ? 'self' : 'none',
    };
  }

  const [space, membership] = await Promise.all([
    transaction.get(db.doc(`spaces/${spaceId}`)),
    transaction.get(db.doc(`spaces/${spaceId}/members/${actorUid}`)),
  ]);
  const isAdmin = space.data()?.ownerUid === actorUid ||
    membership.data()?.role === 'admin';
  const linked = new Map<string, string | undefined>();
  for (const actor of manualActors) {
    const manualId = manualIdOf(actor)!;
    const snapshot = await transaction.get(
      db.doc(`spaces/${spaceId}/manualParticipants/${manualId}`),
    );
    linked.set(actor, (snapshot.data()?.linkedUid as string | undefined) ??
      undefined);
  }
  const roleOf = (actor: string): EconomicActingRole => economicActingRole({
    actor,
    viewerUid: actorUid,
    viewerIsSpaceAdmin: isAdmin,
    linkedUid: linked.get(actor),
  });
  return { receiverRole: roleOf(receiverUid), payerRole: roleOf(payerUid) };
}

export const resolveEconomicPayment = onCall(async (request) => {
  const actorUid = requireFullAccount(request.auth);
  const data = request.data as Record<string, unknown> | null;
  const paymentId = data?.paymentId;
  const action = data?.action;
  if (
    typeof paymentId !== 'string' ||
    !paymentIdPattern.test(paymentId) ||
    (action !== 'confirm' && action !== 'cancel' && action !== 'reject')
  ) {
    throw new HttpsError('invalid-argument', 'PAYMENT_DATA_INVALID');
  }

  const db = getFirestore();
  const ref = db.collection('economicPayments').doc(paymentId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError('not-found', 'PAYMENT_NOT_FOUND');
    const payment = snapshot.data()!;
    // Un cobro dirigido a alguien SIN cuenta lo resuelve quien lo representa
    // (ADR-038); entre dos cuentas nadie más que su titular.
    const authority = await actingAuthorityOn(
      db,
      transaction,
      payment,
      actorUid,
    );
    const target = resolvePaymentTransition(
      payment,
      actorUid,
      action as ResolveAction,
      authority,
    );
    if (payment.status === target) return { paymentId, status: target };
    transaction.update(ref, {
      status: target,
      stateHistory: FieldValue.arrayUnion({
        status: target,
        at: Timestamp.now(),
        byUid: actorUid,
      }),
      updatedAt: FieldValue.serverTimestamp(),
      ...(target === 'confirmed'
        ? { confirmedAt: FieldValue.serverTimestamp() }
        : { cancelledAt: FieldValue.serverTimestamp() }),
    });
    return { paymentId, status: target };
  });
});
