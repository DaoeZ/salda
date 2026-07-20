import assert from 'node:assert/strict';
import { test } from 'node:test';

import { HttpsError } from 'firebase-functions/v2/https';

import {
  allocatePaymentToEntries,
  availablePaymentAmount,
  economicPairId,
  resolvePaymentTransition,
  validateCreatePaymentInput,
} from '../economicPayments.js';

const balance = {
  firstUid: 'alba',
  secondUid: 'pedro',
  currency: 'EUR',
  originalFirstToSecond: 0,
  originalSecondToFirst: 2500,
  confirmedFirstToSecond: 0,
  confirmedSecondToFirst: 1000,
  pendingFirstToSecond: 0,
  pendingSecondToFirst: 300,
  signedOutstanding: -1500,
};

test('importe disponible descuenta confirmados y reservas pendientes', () => {
  assert.equal(availablePaymentAmount(balance, 'pedro', 'alba'), 1200);
  assert.equal(availablePaymentAmount(balance, 'alba', 'pedro'), 0);
});

test('el identificador de pareja no depende del orden', () => {
  assert.equal(economicPairId('alba', 'pedro'), economicPairId('pedro', 'alba'));
});

test('valida céntimos, moneda e idempotencia', () => {
  assert.deepEqual(validateCreatePaymentInput({
    receiverUid: 'alba',
    amount: 1000,
    currency: 'EUR',
    idempotencyKey: '1234567890abcdef',
  }), {
    receiverUid: 'alba',
    amount: 1000,
    currency: 'EUR',
    idempotencyKey: '1234567890abcdef',
  });
  for (const invalid of [
    { receiverUid: 'alba', amount: 0, currency: 'EUR', idempotencyKey: '1234567890abcdef' },
    { receiverUid: 'alba', amount: 1.5, currency: 'EUR', idempotencyKey: '1234567890abcdef' },
    { receiverUid: 'alba', amount: 1, currency: 'eur', idempotencyKey: '1234567890abcdef' },
    { receiverUid: 'alba', amount: 1, currency: 'EUR', idempotencyKey: 'corta' },
  ]) {
    assert.throws(
      () => validateCreatePaymentInput(invalid),
      (error: unknown) => error instanceof HttpsError &&
        error.code === 'invalid-argument',
    );
  }
});

test('asigna pagos a tickets de forma determinista y respeta reservas', () => {
  const entries = [
    { id: 'ticket-b', amount: 1000 },
    { id: 'ticket-a', amount: 600 },
  ];
  assert.deepEqual(allocatePaymentToEntries(900, entries), {
    'ticket-a': 600,
    'ticket-b': 300,
  });
  assert.deepEqual(
    allocatePaymentToEntries(500, entries, new Map([['ticket-a', 400]])),
    { 'ticket-a': 200, 'ticket-b': 300 },
  );
  assert.throws(() => allocatePaymentToEntries(2000, entries));
});

test('solo receptor confirma/rechaza y solo pagador cancela', () => {
  const payment = {
    source: 'user', status: 'pending', payerUid: 'a', receiverUid: 'b',
  };
  assert.equal(resolvePaymentTransition(payment, 'b', 'confirm'), 'confirmed');
  assert.equal(resolvePaymentTransition(payment, 'b', 'reject'), 'cancelled');
  assert.equal(resolvePaymentTransition(payment, 'a', 'cancel'), 'cancelled');
  assert.throws(() => resolvePaymentTransition(payment, 'c', 'confirm'));
  assert.throws(() => resolvePaymentTransition(payment, 'a', 'reject'));
  assert.throws(() => resolvePaymentTransition(payment, 'b', 'cancel'));
});
