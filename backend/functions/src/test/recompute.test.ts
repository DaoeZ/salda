/**
 * Tests del núcleo puro de recompute (computeAggregates): totales, balances,
 * sincronización de liquidaciones (preservar marked, congelar confirmed) y
 * saneamiento de datos huérfanos. La parte Firestore es un envoltorio fino.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  computeAggregates,
  type SessionSnapshot,
} from '../recompute.js';

const base = (): SessionSnapshot => ({
  splitModeDefault: 'byItem',
  participants: [
    { id: 'p1', isOwner: true, order: 0 },
    { id: 'p2', order: 1 },
    { id: 'p3', order: 2 },
  ],
  accounts: [
    {
      id: 'hotel',
      tickets: [
        {
          id: 't1',
          grandTotal: 3000,
          paidByParticipantId: 'p1',
          lines: [
            {
              id: 'l1',
              totalPrice: 3000,
              assignment: { type: 'all', participants: {} },
            },
          ],
        },
      ],
    },
    {
      id: 'gasolina',
      tickets: [
        {
          id: 't2',
          grandTotal: 600,
          paidByParticipantId: 'p2',
          splitModeOverride: 'equal',
          lines: [],
        },
      ],
    },
  ],
  settlements: [],
});

test('totales por cuenta y de sesión', () => {
  const r = computeAggregates(base());
  assert.deepEqual(r.accountTotals, {
    hotel: { grandTotal: 3000 },
    gasolina: { grandTotal: 600 },
  });
  assert.equal(r.sessionTotals.grandTotal, 3600);
});

test('balances multi-pagador y liquidaciones mínimas', () => {
  const r = computeAggregates(base());
  // Consumos: hotel 1000/persona; gasolina 200/persona.
  // p1 pagó 3000, consumió 1200 → +1800; p2 pagó 600, consumió 1200 → −600;
  // p3 −1200.
  assert.equal(r.balances.p1.net, 1800);
  assert.equal(r.balances.p2.net, -600);
  assert.equal(r.balances.p3.net, -1200);
  assert.deepEqual(r.settlementOps.create, [
    { from: 'p3', to: 'p1', amount: 1200 },
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
  assert.equal(r.pendingSettlements, 2);
});

test('una liquidación marked idéntica se conserva (no se machaca)', () => {
  const s = base();
  s.settlements = [
    { id: 'st1', from: 'p3', to: 'p1', amount: 1200, state: 'marked' },
  ];
  const r = computeAggregates(s);
  assert.ok(r.settlementOps.keep.includes('st1'));
  assert.deepEqual(r.settlementOps.remove, []);
  assert.deepEqual(r.settlementOps.create, [
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
  assert.equal(r.sessionTotals.settledMarked, 1200);
  assert.equal(r.pendingSettlements, 1);
});

test('si cambia el importe objetivo, la pendiente/marked se regenera', () => {
  const s = base();
  s.settlements = [
    { id: 'st1', from: 'p3', to: 'p1', amount: 999, state: 'marked' },
  ];
  const r = computeAggregates(s);
  assert.deepEqual(r.settlementOps.remove, ['st1']);
  assert.equal(
    r.settlementOps.create.some(
      (c) => c.from === 'p3' && c.amount === 1200,
    ),
    true,
  );
});

test('las confirmadas se congelan: reducen lo pendiente y se conservan', () => {
  const s = base();
  s.settlements = [
    { id: 'st1', from: 'p3', to: 'p1', amount: 1200, state: 'confirmed' },
  ];
  const r = computeAggregates(s);
  assert.ok(r.settlementOps.keep.includes('st1'));
  assert.equal(r.sessionTotals.settledConfirmed, 1200);
  assert.equal(r.balances.p3.outstanding, 0);
  assert.deepEqual(r.settlementOps.create, [
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
});

test('saneamiento: pid desconocido en asignación y pagador borrado', () => {
  const s = base();
  s.accounts[0].tickets[0].lines[0].assignment = {
    type: 'shared',
    participants: { p2: 1, fantasma: 3 },
  };
  s.accounts[1].tickets[0].paidByParticipantId = 'borrado';
  const r = computeAggregates(s);
  // La línea queda para p2; el pagador huérfano recae en el owner (p1).
  assert.equal(r.balances.p2.consumed, 3000 + 200);
  assert.equal(r.balances.p1.paid, 3000 + 600);
  // El sistema sigue siendo exacto: Σ outstanding == 0.
  const sum = Object.values(r.balances).reduce(
    (a, b) => a + b.outstanding,
    0,
  );
  assert.equal(sum, 0);
});

test('participante inactivo no entra en el reparto', () => {
  const s = base();
  s.participants[2] = { id: 'p3', order: 2, active: false };
  s.accounts[1].tickets[0].grandTotal = 600;
  const r = computeAggregates(s);
  assert.equal(r.balances.p3, undefined);
  // hotel 'all' entre p1 y p2: 1500 cada uno.
  assert.equal(r.balances.p1.consumed, 1500 + 300);
});

test('determinismo: el orden de participantes lo fija `order`', () => {
  const s = base();
  // Mismo contenido, participantes desordenados en la lectura.
  s.participants = [
    { id: 'p3', order: 2 },
    { id: 'p1', isOwner: true, order: 0 },
    { id: 'p2', order: 1 },
  ];
  const r1 = computeAggregates(base());
  const r2 = computeAggregates(s);
  assert.deepEqual(r2.settlementOps.create, r1.settlementOps.create);
  assert.deepEqual(r2.balances, r1.balances);
});
