import assert from 'node:assert/strict';
import { test } from 'node:test';

import { HttpsError } from 'firebase-functions/v2/https';

import {
  planEntrySettlements,
  resolvePaymentTransition,
  validateSettleEntriesInput,
  type EntrySettlementContext,
} from '../economicPayments.js';

const base = {
  currency: 'EUR',
  memberUids: ['edgar', 'test'],
  sessionId: 's1',
  spaceId: 'space1',
  allocated: 0,
};

/** Familycash 6,75 y «t familycash» 7,98: Test debe a Edgar 14,73. */
const contexts = (
  overrides: Partial<EntrySettlementContext> = {},
): Map<string, EntrySettlementContext> => new Map([
  ['e_familycash', {
    ...base,
    id: 'e_familycash',
    debtorUid: 'test',
    creditorUid: 'edgar',
    amount: 675,
    creditorRole: 'self',
    debtorRole: 'none',
    ...overrides,
  } as EntrySettlementContext],
  ['e_tfamilycash', {
    ...base,
    id: 'e_tfamilycash',
    debtorUid: 'test',
    creditorUid: 'edgar',
    amount: 798,
    creditorRole: 'self',
    debtorRole: 'none',
    ...overrides,
  } as EntrySettlementContext],
]);

const available = (cents = 1473) =>
  new Map([[`EUR\0test\0edgar`, cents]]);

const plan = (
  requests: Array<{ entryId: string; amount?: number }>,
  map = contexts(),
  avail = available(),
) => planEntrySettlements({
  requests,
  contexts: map,
  availableByDirection: avail,
  idempotencyKey: '1234567890abcdef',
});

test('el receptor confirma una obligación sin declaración previa del deudor', () => {
  const drafts = plan([{ entryId: 'e_familycash' }]);
  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].amount, 675);
  assert.equal(drafts[0].status, 'confirmed');
  assert.equal(drafts[0].entryId, 'e_familycash');
  assert.deepEqual(drafts[0].sessionId, 's1');
});

test('el camino normal no obliga a teclear el importe', () => {
  // Sin `amount` se liquida el pendiente completo de ESA obligación.
  assert.equal(plan([{ entryId: 'e_tfamilycash' }])[0].amount, 798);
});

test('confirmar varias NO las funde en una liquidación agregada', () => {
  const drafts = plan([
    { entryId: 'e_familycash' },
    { entryId: 'e_tfamilycash' },
  ]);
  assert.equal(drafts.length, 2);
  assert.deepEqual(drafts.map((d) => d.amount).sort(), [675, 798]);
  // Nunca aparece el agregado de 14,73 como obligación nueva.
  assert.ok(!drafts.some((draft) => draft.amount === 1473));
  assert.deepEqual(
    drafts.map((draft) => draft.entryId).sort(),
    ['e_familycash', 'e_tfamilycash'],
  );
});

test('un pago parcial pertenece a SU obligación', () => {
  const drafts = plan([{ entryId: 'e_familycash', amount: 500 }]);
  assert.equal(drafts[0].amount, 500);
  assert.equal(drafts[0].entryId, 'e_familycash');
});

test('no se puede liquidar más de lo que queda vivo en la obligación', () => {
  assert.throws(
    () => plan([{ entryId: 'e_familycash', amount: 700 }]),
    (error: unknown) => error instanceof HttpsError &&
      error.code === 'failed-precondition',
  );
});

test('lo ya asignado por otro pago reduce el pendiente de la obligación', () => {
  const map = contexts();
  map.get('e_familycash')!.allocated = 500;
  assert.equal(plan([{ entryId: 'e_familycash' }], map)[0].amount, 175);
  assert.throws(() => plan([{ entryId: 'e_familycash', amount: 200 }], map));
});

test('una obligación ya saldada no se vuelve a cobrar', () => {
  const map = contexts();
  map.get('e_familycash')!.allocated = 675;
  assert.throws(
    () => plan([{ entryId: 'e_familycash' }], map),
    (error: unknown) => error instanceof HttpsError &&
      error.message === 'ENTRY_ALREADY_SETTLED',
  );
});

test('el saldo bilateral vivo es un techo: no se cobra dos veces', () => {
  // La deuda ya se saldó por el flujo de liquidación de la sesión, que no
  // deja asignación por ticket: el disponible bilateral es 0.
  assert.throws(
    () => plan([{ entryId: 'e_familycash' }], contexts(), available(0)),
    (error: unknown) => error instanceof HttpsError &&
      error.message === 'PAYMENT_EXCEEDS_BALANCE',
  );
  // Y en una confirmación múltiple el techo se aplica al conjunto.
  assert.throws(
    () => plan(
      [{ entryId: 'e_familycash' }, { entryId: 'e_tfamilycash' }],
      contexts(),
      available(1000),
    ),
  );
});

test('el deudor solo DECLARA: su liquidación nace pendiente', () => {
  const map = contexts({ creditorRole: 'none', debtorRole: 'self' });
  const drafts = planEntrySettlements({
    requests: [{ entryId: 'e_familycash' }],
    contexts: map,
    availableByDirection: available(),
    idempotencyKey: '1234567890abcdef',
  });
  assert.equal(drafts[0].status, 'pending');
});

test('un tercero sin título sobre ninguna de las dos partes no puede', () => {
  const map = contexts({ creditorRole: 'none', debtorRole: 'none' });
  assert.throws(
    () => plan([{ entryId: 'e_familycash' }], map),
    (error: unknown) => error instanceof HttpsError &&
      error.code === 'permission-denied',
  );
});

test('representar a quien no tiene cuenta queda registrado en el pago', () => {
  const map = contexts({
    creditorUid: 'manual:javi',
    creditorRole: 'representative',
    memberUids: ['test'],
  });
  const avail = new Map([[`EUR\0test\0manual:javi`, 1473]]);
  const drafts = plan([{ entryId: 'e_familycash' }], map, avail);
  assert.equal(drafts[0].status, 'confirmed');
  assert.equal(drafts[0].onBehalfOfManualId, 'javi');
  assert.equal(drafts[0].receiverUid, 'manual:javi');
});

test('una obligación inexistente no se inventa', () => {
  assert.throws(
    () => plan([{ entryId: 'no_existe' }]),
    (error: unknown) => error instanceof HttpsError &&
      error.code === 'not-found',
  );
});

test('valida entradas, importes e idempotencia', () => {
  assert.deepEqual(
    validateSettleEntriesInput({
      entries: [{ entryId: 'e1' }, { entryId: 'e2', amount: 500 }],
      idempotencyKey: '1234567890abcdef',
    }),
    {
      entries: [{ entryId: 'e1' }, { entryId: 'e2', amount: 500 }],
      idempotencyKey: '1234567890abcdef',
    },
  );
  for (const invalid of [
    { entries: [], idempotencyKey: '1234567890abcdef' },
    { entries: [{ entryId: 'e1' }], idempotencyKey: 'corta' },
    { entries: [{ entryId: 'e1', amount: 0 }], idempotencyKey: '1234567890abcdef' },
    { entries: [{ entryId: 'e1', amount: 1.5 }], idempotencyKey: '1234567890abcdef' },
    { entries: [{ entryId: 'e1' }, { entryId: 'e1' }], idempotencyKey: '1234567890abcdef' },
    { entries: [{ entryId: 'con espacio' }], idempotencyKey: '1234567890abcdef' },
    { entries: Array.from({ length: 26 }, (_, i) => ({ entryId: `e${i}` })),
      idempotencyKey: '1234567890abcdef' },
  ]) {
    assert.throws(
      () => validateSettleEntriesInput(invalid),
      (error: unknown) => error instanceof HttpsError &&
        error.code === 'invalid-argument',
    );
  }
});

test('quien representa a un receptor sin cuenta confirma su declaración', () => {
  const payment = {
    source: 'user',
    status: 'pending',
    payerUid: 'test',
    receiverUid: 'manual:javi',
  };
  assert.equal(
    resolvePaymentTransition(payment, 'edgar', 'confirm', {
      receiverRole: 'representative',
      payerRole: 'none',
    }),
    'confirmed',
  );
  // Y sin ese título no puede, aunque sea administrador de otra cosa.
  assert.throws(
    () => resolvePaymentTransition(payment, 'edgar', 'confirm', {
      receiverRole: 'none',
      payerRole: 'none',
    }),
    (error: unknown) => error instanceof HttpsError &&
      error.code === 'permission-denied',
  );
});
