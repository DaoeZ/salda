import { createHash } from 'node:crypto';

import {
  FieldValue,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  computeEconomicLedger,
  type BilateralEconomicBalance,
  type EconomicObligation,
  type EconomicPaymentRecord,
} from './domain/economicLedger.js';

const idempotencyPattern = /^[A-Za-z0-9_-]{16,80}$/;
const paymentIdPattern = /^[A-Za-z0-9_-]{1,500}$/;

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

export function resolvePaymentTransition(
  payment: Record<string, unknown>,
  actorUid: string,
  action: ResolveAction,
): 'confirmed' | 'cancelled' {
  if (payment.source !== 'user') {
    throw new HttpsError('failed-precondition', 'LEGACY_PAYMENT_READ_ONLY');
  }
  const target = action === 'confirm' ? 'confirmed' : 'cancelled';
  if (payment.status === target) return target;
  if (payment.status !== 'pending') {
    throw new HttpsError('failed-precondition', 'PAYMENT_ALREADY_RESOLVED');
  }
  if (
    ((action === 'confirm' || action === 'reject') &&
      payment.receiverUid !== actorUid) ||
    (action === 'cancel' && payment.payerUid !== actorUid)
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
    const target = resolvePaymentTransition(
      payment,
      actorUid,
      action as ResolveAction,
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
