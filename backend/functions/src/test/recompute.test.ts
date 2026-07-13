/**
 * Tests del núcleo puro de recompute: totales, balances, sincronización de
 * liquidaciones con IDs DETERMINISTAS (idempotente bajo concurrencia — la
 * causa raíz del bug de pagos duplicados del MVP) y saneamiento de datos.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  computeAggregates,
  settlementId,
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

test('balances multi-pagador y objetivos con id determinista', () => {
  const r = computeAggregates(base());
  assert.equal(r.balances.p1.net, 1800);
  assert.equal(r.balances.p2.net, -600);
  assert.equal(r.balances.p3.net, -1200);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p3', to: 'p1', amount: 1200 },
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
  assert.equal(settlementId(r.settlementSync.writes[0]), 'pending_p3_p1');
  assert.equal(r.pendingSettlements, 2);
});

test('marked con el mismo importe NO se toca (se preserva el aviso de pago)',
    () => {
  const s = base();
  s.settlements = [
    { id: 'pending_p3_p1', from: 'p3', to: 'p1', amount: 1200, state: 'marked' },
  ];
  const r = computeAggregates(s);
  assert.deepEqual(r.settlementSync.untouched, ['pending_p3_p1']);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
  assert.deepEqual(r.settlementSync.removals, []);
  assert.equal(r.sessionTotals.settledMarked, 1200);
  assert.equal(r.pendingSettlements, 1);
});

test('si cambia el importe, el MISMO doc se sobreescribe a pending', () => {
  const s = base();
  s.settlements = [
    { id: 'pending_p3_p1', from: 'p3', to: 'p1', amount: 999, state: 'marked' },
  ];
  const r = computeAggregates(s);
  assert.ok(r.settlementSync.writes.some(
      (w) => settlementId(w) === 'pending_p3_p1' && w.amount === 1200));
  assert.deepEqual(r.settlementSync.removals, []);
  assert.equal(r.sessionTotals.settledMarked, 0);
});

test('duplicados legacy (id aleatorio) se purgan', () => {
  const s = base();
  s.settlements = [
    { id: 'abc123', from: 'p3', to: 'p1', amount: 1200, state: 'pending' },
    { id: 'def456', from: 'p3', to: 'p1', amount: 1200, state: 'pending' },
  ];
  const r = computeAggregates(s);
  // Ambos se retiran y se escribe UNO con id determinista.
  assert.deepEqual(new Set(r.settlementSync.removals),
      new Set(['abc123', 'def456']));
  assert.ok(r.settlementSync.writes.some(
      (w) => settlementId(w) === 'pending_p3_p1'));
});

test('las confirmadas se congelan: reducen lo pendiente y jamás se tocan',
    () => {
  const s = base();
  s.settlements = [
    { id: 'x1', from: 'p3', to: 'p1', amount: 1200, state: 'confirmed' },
  ];
  const r = computeAggregates(s);
  assert.equal(r.sessionTotals.settledConfirmed, 1200);
  assert.equal(r.balances.p3.outstanding, 0);
  assert.ok(!r.settlementSync.removals.includes('x1'));
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
});

test('REGRESIÓN caso real: Lidl confirmado + gasto manual de 55 €', () => {
  // Alba (p2) y Paula (p3) debían 9 € cada una por el Lidl; el owner (p1)
  // confirmó ambos pagos. Después se añade un gasto manual de 55 € a
  // medias entre los tres, pagado por el owner.
  const s: SessionSnapshot = {
    splitModeDefault: 'byItem',
    participants: [
      { id: 'p1', isOwner: true, order: 0 },
      { id: 'p2', order: 1 },
      { id: 'p3', order: 2 },
    ],
    accounts: [
      {
        id: 'lidl',
        tickets: [{
          id: 't1',
          grandTotal: 1800,
          paidByParticipantId: 'p1',
          lines: [
            { id: 'l1', totalPrice: 900,
              assignment: { type: 'one', participants: { p2: 1 } } },
            { id: 'l2', totalPrice: 900,
              assignment: { type: 'one', participants: { p3: 1 } } },
          ],
        }],
      },
      {
        id: 'manual',
        tickets: [{
          id: 't2',
          grandTotal: 5500,
          paidByParticipantId: 'p1',
          splitModeOverride: 'equal',
          lines: [],
        }],
      },
    ],
    settlements: [
      { id: 'a', from: 'p2', to: 'p1', amount: 900, state: 'confirmed' },
      { id: 'b', from: 'p3', to: 'p1', amount: 900, state: 'confirmed' },
    ],
  };
  const r = computeAggregates(s);
  // 5500/3 = 1834/1833/1833 (resto mayor, orden p1,p2,p3).
  assert.equal(r.balances.p2.outstanding, -1833);
  assert.equal(r.balances.p3.outstanding, -1833);
  // Exactamente UNA pendiente nueva por persona, sin duplicados ni restos.
  assert.deepEqual(
    r.settlementSync.writes.map((w) => [settlementId(w), w.amount]).sort(),
    [['pending_p2_p1', 1833], ['pending_p3_p1', 1833]],
  );
  assert.deepEqual(r.settlementSync.removals, []);
  assert.equal(r.sessionTotals.settledConfirmed, 1800);
  assert.equal(r.pendingSettlements, 2);
});

test('idempotencia: aplicar el resultado y recalcular no produce cambios',
    () => {
  const s = base();
  const first = computeAggregates(s);

  // Simula el estado tras aplicar las escrituras (como harían N ejecuciones
  // concurrentes: mismo id, mismo contenido).
  s.settlements = first.settlementSync.writes.map((w) => ({
    id: settlementId(w),
    from: w.from,
    to: w.to,
    amount: w.amount,
    state: 'pending' as const,
  }));
  const second = computeAggregates(s);

  assert.deepEqual(second.settlementSync.writes, []);
  assert.deepEqual(second.settlementSync.removals, []);
  assert.deepEqual(new Set(second.settlementSync.untouched),
      new Set(s.settlements.map((st) => st.id)));
  assert.deepEqual(second.balances, first.balances);
});

test('saneamiento: pid desconocido en asignación y pagador borrado', () => {
  const s = base();
  s.accounts[0].tickets[0].lines[0].assignment = {
    type: 'shared',
    participants: { p2: 1, fantasma: 3 },
  };
  s.accounts[1].tickets[0].paidByParticipantId = 'borrado';
  const r = computeAggregates(s);
  assert.equal(r.balances.p2.consumed, 3000 + 200);
  assert.equal(r.balances.p1.paid, 3000 + 600);
  const sum = Object.values(r.balances).reduce(
    (a, b) => a + b.outstanding, 0);
  assert.equal(sum, 0);
});

test('participante inactivo no entra en el reparto', () => {
  const s = base();
  s.participants[2] = { id: 'p3', order: 2, active: false };
  const r = computeAggregates(s);
  assert.equal(r.balances.p3, undefined);
  assert.equal(r.balances.p1.consumed, 1500 + 300);
});

test('determinismo: el orden de participantes lo fija `order`', () => {
  const s = base();
  s.participants = [
    { id: 'p3', order: 2 },
    { id: 'p1', isOwner: true, order: 0 },
    { id: 'p2', order: 1 },
  ];
  const r1 = computeAggregates(base());
  const r2 = computeAggregates(s);
  assert.deepEqual(r2.settlementSync.writes, r1.settlementSync.writes);
  assert.deepEqual(r2.balances, r1.balances);
});
