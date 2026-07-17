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
  // El denominador son las transferencias necesarias (12 € + 6 €), no los
  // 36 € gastados.
  assert.equal(r.sessionTotals.settlementRequired, 1800);
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
  assert.equal(r.sessionTotals.settledConfirmed, 0);
  assert.equal(r.sessionTotals.settlementRequired, 1800);
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
  assert.equal(r.sessionTotals.settlementRequired, 1800);
  assert.equal(r.balances.p3.outstanding, 0);
  assert.equal(r.balances.p2.outstanding, -600);
  assert.ok(!r.settlementSync.removals.includes('x1'));
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 600 },
  ]);
});

test('todas las obligaciones confirmadas dejan saldo cero y progreso 100 %',
    () => {
  const s = base();
  s.settlements = [
    { id: 'c1', from: 'p3', to: 'p1', amount: 1200, state: 'confirmed' },
    { id: 'c2', from: 'p2', to: 'p1', amount: 600, state: 'confirmed' },
  ];
  const r = computeAggregates(s);

  for (const balance of Object.values(r.balances)) {
    assert.equal(balance.outstanding, 0);
  }
  assert.equal(r.sessionTotals.settledConfirmed, 1800);
  assert.equal(r.sessionTotals.settlementRequired, 1800);
  assert.equal(r.pendingSettlements, 0);
  assert.deepEqual(r.settlementSync.writes, []);
});

test('si cada persona pagó lo suyo, 0/0 representa una sesión saldada', () => {
  const s: SessionSnapshot = {
    splitModeDefault: 'equal',
    participants: [
      { id: 'p1', isOwner: true, order: 0 },
      { id: 'p2', order: 1 },
    ],
    accounts: [{
      id: 'a',
      tickets: [
        {
          id: 't1',
          grandTotal: 1000,
          paidByParticipantId: 'p1',
          lines: [],
        },
        {
          id: 't2',
          grandTotal: 1000,
          paidByParticipantId: 'p2',
          lines: [],
        },
      ],
    }],
    settlements: [],
  };
  const r = computeAggregates(s);

  assert.equal(r.sessionTotals.settlementRequired, 0);
  assert.equal(r.sessionTotals.settledConfirmed, 0);
  assert.equal(r.balances.p1.outstanding, 0);
  assert.equal(r.balances.p2.outstanding, 0);
  assert.deepEqual(r.settlementSync.writes, []);
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
  // 18 € ya confirmados + 36,66 € residuales del gasto nuevo.
  assert.equal(r.sessionTotals.settlementRequired, 5466);
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

// ─────────────────────────────────────────────────────────────────────────
// "CADA UNO PAGA LO SUYO": jamás una media previa; lo no reclamado es del
// pagador. Estos tests blindan el bug reportado en pruebas reales para que
// no vuelva NUNCA.
// ─────────────────────────────────────────────────────────────────────────

/** Sesión de un solo ticket byItem, pagado por p1 (owner), 3 personas. */
function byItem(
  grandTotal: number,
  lines: SessionSnapshot['accounts'][0]['tickets'][0]['lines'],
  participantIds = ['p1', 'p2', 'p3'],
): SessionSnapshot {
  return {
    splitModeDefault: 'byItem',
    participants: participantIds.map((id, i) => ({
      id,
      isOwner: i === 0,
      order: i,
    })),
    accounts: [
      {
        id: 'a',
        tickets: [{ id: 't', grandTotal, paidByParticipantId: 'p1', lines }],
      },
    ],
    settlements: [],
  };
}

const one = (pid: string) => ({ type: 'one', participants: { [pid]: 1 } });
const shared = (...pids: string[]) => ({
  type: 'shared',
  participants: Object.fromEntries(pids.map((p) => [p, 1])),
});
const unassigned = { type: 'unassigned', participants: {} };

test('BUG REPORTADO: 30€/3, uno coge algo de 5€, el resto SIN reclamar → ' +
    'NO hay media previa; lo no reclamado lo cubre el pagador', () => {
  // Total 30€: coca 5€ (p2) + resto 25€ aún sin asignar. El bug daba
  // ~13,33 a p2 (8,33 de media + 5 de la coca). Correcto: p2 paga SOLO 5€.
  const r = computeAggregates(
    byItem(3000, [
      { id: 'coca', totalPrice: 500, assignment: one('p2') },
      { id: 'resto', totalPrice: 2500, assignment: unassigned },
    ]),
  );
  assert.equal(r.balances.p2.consumed, 500); // exactamente su coca, sin media
  assert.equal(r.balances.p3.consumed, 0); // no cogió nada → 0, sin media
  assert.equal(r.balances.p1.consumed, 2500); // el pagador cubre lo no reclamado
  // Σ consumo == grandTotal, siempre.
  assert.equal(
    r.balances.p1.consumed + r.balances.p2.consumed + r.balances.p3.consumed,
    3000,
  );
  // p2 debe 5€ a p1; p3 no debe nada.
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 500 },
  ]);
});

test('a medida que se reclama, la parte del pagador se reduce a lo suyo', () => {
  // Todo reclamado: p1 su plato (10), p2 (10), p3 (10). Pagador solo lo suyo.
  const r = computeAggregates(
    byItem(3000, [
      { id: 'l1', totalPrice: 1000, assignment: one('p1') },
      { id: 'l2', totalPrice: 1000, assignment: one('p2') },
      { id: 'l3', totalPrice: 1000, assignment: one('p3') },
    ]),
  );
  assert.equal(r.balances.p1.consumed, 1000);
  assert.equal(r.balances.p2.consumed, 1000);
  assert.equal(r.balances.p3.consumed, 1000);
  assert.equal(r.balances.p1.net, 3000 - 1000); // pagó 30, consumió 10
});

test('todos dejan de compartir (todo vuelve a sin asignar) → todo al pagador',
    () => {
  const r = computeAggregates(byItem(3000, [
    { id: 'l1', totalPrice: 3000, assignment: unassigned },
  ]));
  assert.equal(r.balances.p1.consumed, 3000);
  assert.equal(r.balances.p2.consumed, 0);
  assert.equal(r.balances.p3.consumed, 0);
  assert.deepEqual(r.settlementSync.writes, []); // nadie debe nada al pagador
});

test('compartido entre 2 / 3 / 4 se divide a partes iguales', () => {
  // 2 comparten unas bravas de 6€ (el resto lo cubre el pagador p1).
  let r = computeAggregates(byItem(600, [
    { id: 'bravas', totalPrice: 600, assignment: shared('p2', 'p3') },
  ]));
  assert.equal(r.balances.p2.consumed, 300);
  assert.equal(r.balances.p3.consumed, 300);

  // 3 comparten (incluye al pagador): 900/3 = 300 cada uno.
  r = computeAggregates(byItem(900, [
    { id: 'l', totalPrice: 900, assignment: shared('p1', 'p2', 'p3') },
  ]));
  assert.equal(r.balances.p1.consumed, 300);
  assert.equal(r.balances.p2.consumed, 300);
  assert.equal(r.balances.p3.consumed, 300);

  // 4 comparten: 1000/4 = 250 cada uno.
  r = computeAggregates(byItem(
    1000,
    [{ id: 'l', totalPrice: 1000, assignment: shared('p1', 'p2', 'p3', 'p4') }],
    ['p1', 'p2', 'p3', 'p4'],
  ));
  for (const p of ['p1', 'p2', 'p3', 'p4']) {
    assert.equal(r.balances[p].consumed, 250);
  }
});

test('una persona deja de compartir → los que quedan se reparten', () => {
  // Antes p2+p3 compartían; p3 se sale → p2 solo (con lo no reclamado al pagador).
  const r = computeAggregates(byItem(600, [
    { id: 'bravas', totalPrice: 600, assignment: shared('p2') },
  ]));
  assert.equal(r.balances.p2.consumed, 600);
  assert.equal(r.balances.p3.consumed, 0);
});

test('descuentos e IVA (grandTotal != subtotal) se prorratean, un solo redondeo',
    () => {
  // Subtotal líneas 1000, grandTotal 1100 (IVA 10%): cada consumo escala ×1,1.
  const r = computeAggregates(byItem(1100, [
    { id: 'l1', totalPrice: 500, assignment: one('p2') },
    { id: 'l2', totalPrice: 500, assignment: one('p3') },
  ]));
  assert.equal(r.balances.p2.consumed, 550);
  assert.equal(r.balances.p3.consumed, 660 - 110); // 550
  assert.equal(r.balances.p1.consumed, 0);
  assert.equal(
    r.balances.p1.consumed + r.balances.p2.consumed + r.balances.p3.consumed,
    1100,
  );
});

test('ticket grande con resto: Σ consumo == grandTotal exacto', () => {
  // 100,03 € entre 3 que comparten una línea: sin céntimos perdidos.
  const r = computeAggregates(byItem(10003, [
    { id: 'l', totalPrice: 10003, assignment: shared('p1', 'p2', 'p3') },
  ]));
  const sum =
    r.balances.p1.consumed + r.balances.p2.consumed + r.balances.p3.consumed;
  assert.equal(sum, 10003);
});

test('múltiples productos compartidos por grupos distintos + individual + ' +
    'sin reclamar al pagador, todo a la vez', () => {
  // 4 personas. bravas(6€) p2+p3; nachos(4€) p3+p4; cerveza(3€) p2;
  // postre(2€) sin reclamar → pagador p1. grandTotal 15€ (= subtotal).
  const r = computeAggregates(byItem(
    1500,
    [
      { id: 'bravas', totalPrice: 600, assignment: shared('p2', 'p3') },
      { id: 'nachos', totalPrice: 400, assignment: shared('p3', 'p4') },
      { id: 'cerveza', totalPrice: 300, assignment: one('p2') },
      { id: 'postre', totalPrice: 200, assignment: unassigned },
    ],
    ['p1', 'p2', 'p3', 'p4'],
  ));
  // p2: 300 (media bravas) + 300 (cerveza) = 600
  assert.equal(r.balances.p2.consumed, 600);
  // p3: 300 (media bravas) + 200 (media nachos) = 500
  assert.equal(r.balances.p3.consumed, 500);
  // p4: 200 (media nachos) = 200
  assert.equal(r.balances.p4.consumed, 200);
  // p1: postre sin reclamar = 200
  assert.equal(r.balances.p1.consumed, 200);
  assert.equal(
    r.balances.p1.consumed +
      r.balances.p2.consumed +
      r.balances.p3.consumed +
      r.balances.p4.consumed,
    1500,
  );
});

test('modo "a medias" (equal) es indiferente a las asignaciones de línea', () => {
  const r = computeAggregates({
    ...byItem(900, [{ id: 'l', totalPrice: 900, assignment: one('p2') }]),
    splitModeDefault: 'equal',
  });
  assert.equal(r.balances.p1.consumed, 300);
  assert.equal(r.balances.p2.consumed, 300);
  assert.equal(r.balances.p3.consumed, 300);
});

// ─── P2.1: unidades reclamables y residual al pagador ─────────────────────

test('P2.1 unidades: reclamar 1 de 2 flautas deja la otra al pagador', () => {
  // 2 × flauta (2 €/ud, 4 €). Alba (p2) coge UNA: 2 € ella, 2 € el pagador
  // (p1). Antes se llevaba la línea entera.
  const r = computeAggregates(
    byItem(400, [
      {
        id: 'flautas',
        totalPrice: 400,
        quantityMilli: 2000,
        assignment: one('p2'),
      },
    ]),
  );
  assert.equal(r.balances.p2.consumed, 200);
  assert.equal(r.balances.p1.consumed, 200);
  assert.equal(r.balances.p3.consumed, 0);
});

test('P2.1 unidades: Alba y Pedro cubren las 2 unidades; el creador, cero', () => {
  const r = computeAggregates(
    byItem(400, [
      {
        id: 'flautas',
        totalPrice: 400,
        quantityMilli: 2000,
        assignment: shared('p2', 'p3'),
      },
    ]),
  );
  assert.equal(r.balances.p2.consumed, 200);
  assert.equal(r.balances.p3.consumed, 200);
  assert.equal(r.balances.p1.consumed, 0);
});

test('P2.1 unidades: compartir una pizza entre 3 sigue intacto (4 € c/u)', () => {
  const r = computeAggregates(
    byItem(1200, [
      {
        id: 'pizza',
        totalPrice: 1200,
        quantityMilli: 1000,
        assignment: shared('p1', 'p2', 'p3'),
      },
    ]),
  );
  assert.equal(r.balances.p1.consumed, 400);
  assert.equal(r.balances.p2.consumed, 400);
  assert.equal(r.balances.p3.consumed, 400);
});

test('P2.1 unidades: selección explícita del creador + residual, sin duplicar', () => {
  // 3 unidades: el creador (pagador) coge 1, Alba 1, queda 1 sin reclamar.
  // El creador termina con 2 (1 explícita + 1 residual); Alba con 1.
  const r = computeAggregates(
    byItem(600, [
      {
        id: 'triple',
        totalPrice: 600,
        quantityMilli: 3000,
        assignment: shared('p1', 'p2'),
      },
    ]),
  );
  assert.equal(r.balances.p1.consumed, 400);
  assert.equal(r.balances.p2.consumed, 200);
  assert.equal(
    r.balances.p1.consumed + r.balances.p2.consumed + r.balances.p3.consumed,
    600,
  );
});

test('P2.1 unidades: los pesos (0,466 kg) siguen siendo UNA unidad', () => {
  // quantityMilli no múltiplo de 1000 = artículo a peso: seleccionarlo se
  // lleva la línea completa, como siempre.
  const r = computeAggregates(
    byItem(233, [
      {
        id: 'platanos',
        totalPrice: 233,
        quantityMilli: 466,
        assignment: one('p2'),
      },
    ]),
  );
  assert.equal(r.balances.p2.consumed, 233);
  assert.equal(r.balances.p1.consumed, 0);
});

test('P2.1 unidades: ticket antiguo sin quantityMilli se comporta igual', () => {
  const r = computeAggregates(
    byItem(500, [{ id: 'l', totalPrice: 500, assignment: one('p2') }]),
  );
  assert.equal(r.balances.p2.consumed, 500);
  assert.equal(r.balances.p1.consumed, 0);
});

test('P2.2 recompute: una unidad exclusiva y otra compartida son 3/4 y 1/4',
    () => {
  const r = computeAggregates(
    byItem(418, [{
      id: 'flautas',
      totalPrice: 418,
      quantityMilli: 2000,
      assignment: {
        type: 'units',
        schemaVersion: 2,
        units: {
          u0: { p1: true },
          u1: { p1: true, p2: true },
        },
      },
    }]),
  );
  // 209 por unidad; en la compartida el céntimo impar favorece el orden p1.
  assert.equal(r.balances.p1.consumed, 314);
  assert.equal(r.balances.p2.consumed, 104);
  assert.equal(r.balances.p3.consumed, 0);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 104 },
  ]);
});

test('P2.2 recompute: edición repetida y concurrencia convergen sin duplicar',
    () => {
  const snapshot = byItem(600, [{
    id: 'unidades',
    totalPrice: 600,
    quantityMilli: 3000,
    assignment: {
      type: 'units',
      schemaVersion: 2,
      units: { u0: { p2: true }, u1: { p2: true, p3: true } },
    },
  }]);
  const first = computeAggregates(snapshot);
  const second = computeAggregates(structuredClone(snapshot));
  assert.deepEqual(second, first);
  assert.equal(
    Object.values(first.balances).reduce((sum, b) => sum + b.consumed, 0),
    600,
  );
  assert.ok(Object.values(first.balances).every((b) => b.consumed >= 0));
});

test('P2.1 REGRESIÓN Alba/Pedro: tras confirmar el pago de Alba, lo nuevo ' +
    'de Pedro se lo debe a ALBA, no al creador', () => {
  // Edgar (p1) pagó 20 €. Alba (p2) consumió 10 y YA pagó (confirmada).
  // Después Pedro (p3) comparte la mitad de lo de Alba: 5 €.
  // Alba queda a +5 (pagó 10, consume 5) y Pedro a -5 → Pedro paga a ALBA.
  const snapshot = byItem(2000, [
    { id: 'edgar', totalPrice: 1000, assignment: one('p1') },
    { id: 'compartido', totalPrice: 1000, assignment: shared('p2', 'p3') },
  ]);
  snapshot.settlements = [
    {
      id: 'pending_p2_p1',
      from: 'p2',
      to: 'p1',
      amount: 1000,
      state: 'confirmed',
    },
  ];
  const r = computeAggregates(snapshot);
  assert.equal(r.balances.p2.outstanding, 500); // a Alba le deben 5
  assert.equal(r.balances.p3.outstanding, -500); // Pedro debe 5
  assert.equal(r.balances.p1.outstanding, 0); // Edgar ya está en paz
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p3', to: 'p2', amount: 500 },
  ]);
  assert.equal(settlementId(r.settlementSync.writes[0]), 'pending_p3_p2');
});
