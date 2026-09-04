/**
 * A11c: qué le pasa al dinero cuando se CORRIGE un gasto ya pagado.
 *
 * La regla del producto: corregir un ticket nunca borra ni maquilla un pago
 * ya registrado. El pago es un hecho —alguien entregó ese dinero—; la deuda
 * es una consecuencia del gasto y se vuelve a calcular. Si el gasto baja por
 * debajo de lo ya pagado, el saldo se INVIERTE en lugar de inventarse un
 * cuadre.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeAggregates, type SessionSnapshot } from '../recompute.js';

/// Alba (p1) paga; Jorge (p2) consume la línea entera. Es el caso del
/// enunciado: una Coca-Cola asignada a Jorge dentro de un grupo.
const gasto = (totalPrice: number): SessionSnapshot => ({
  splitModeDefault: 'byItem',
  ownerUid: 'uid-alba',
  currency: 'EUR',
  participants: [
    { id: 'p1', isOwner: true, order: 0, userUid: 'uid-alba' },
    { id: 'p2', order: 1, userUid: 'uid-jorge' },
  ],
  accounts: [
    {
      id: 'a1',
      tickets: [
        {
          id: 't1',
          grandTotal: totalPrice,
          paidByParticipantId: 'p1',
          lines: [
            {
              id: 'l1',
              totalPrice,
              assignment: { type: 'one', participants: { p2: 1 } },
            },
          ],
        },
      ],
    },
  ],
  settlements: [],
});

/// Jorge ya pagó 3 € y Alba lo confirmó.
const conPagoConfirmado = (snapshot: SessionSnapshot): SessionSnapshot => ({
  ...snapshot,
  externalConfirmed: [{ from: 'p2', to: 'p1', amount: 300 }],
});

test('A11c antes de corregir: Jorge debe 3 € y con su pago queda saldado',
    () => {
  const r = computeAggregates(conPagoConfirmado(gasto(300)));

  assert.equal(r.balances.p2.consumed, 300);
  assert.equal(r.balances.p2.outstanding, 0);
  assert.equal(r.sessionTotals.settledConfirmed, 300);
  assert.deepEqual(r.settlementSync.writes, []);
});

test('A11c corrección al alza 3 € → 4 €: el pago sobrevive y queda 1 €',
    () => {
  const r = computeAggregates(conPagoConfirmado(gasto(400)));

  // La obligación se rehace entera sobre el gasto corregido…
  assert.equal(r.balances.p2.consumed, 400);
  // …y lo ya pagado sigue ahí, sin tocarlo.
  assert.equal(r.sessionTotals.settledConfirmed, 300);
  // Queda exactamente la diferencia.
  assert.equal(r.balances.p2.outstanding, -100);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p2', to: 'p1', amount: 100 },
  ]);
});

test('A11c corrección a la baja 3 € → 2 €: el saldo se INVIERTE, no se '
    + 'maquilla el pago', () => {
  const r = computeAggregates(conPagoConfirmado(gasto(200)));

  assert.equal(r.balances.p2.consumed, 200);
  // El pago de 3 € permanece intacto: nadie lo recorta para que cuadre.
  assert.equal(r.sessionTotals.settledConfirmed, 300);
  // Jorge pagó de más: ahora le deben a él.
  assert.equal(r.balances.p2.outstanding, 100);
  assert.equal(r.balances.p1.outstanding, -100);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p1', to: 'p2', amount: 100 },
  ]);
});

test('A11c retirar el producto de Jorge: su consumo desaparece y lo pagado '
    + 'se le devuelve', () => {
  const sinLinea = conPagoConfirmado(gasto(300));
  sinLinea.accounts[0].tickets[0].lines = [];
  sinLinea.accounts[0].tickets[0].grandTotal = 0;

  const r = computeAggregates(sinLinea);

  assert.equal(r.balances.p2.consumed, 0);
  assert.equal(r.sessionTotals.settledConfirmed, 300);
  assert.equal(r.balances.p2.outstanding, 300);
  assert.deepEqual(r.settlementSync.writes, [
    { from: 'p1', to: 'p2', amount: 300 },
  ]);
});

/// El caso del enunciado: el ticket dice 15,96 € y el OCR leyó mal UNA línea.
/// `grandTotal` es el dinero realmente pagado; las líneas son los pesos con
/// los que ese dinero se reparte (DC-11, y por eso los vectores dorados
/// tienen tickets con impuestos donde la suma de líneas no llega al total).
const ticketDe1596 = (precioDelProducto: number): SessionSnapshot => ({
  splitModeDefault: 'byItem',
  ownerUid: 'uid-alba',
  currency: 'EUR',
  participants: [
    { id: 'p1', isOwner: true, order: 0, userUid: 'uid-alba' },
    { id: 'p2', order: 1, userUid: 'uid-jorge' },
  ],
  accounts: [
    {
      id: 'a1',
      tickets: [
        {
          id: 't1',
          grandTotal: 1596,
          paidByParticipantId: 'p1',
          lines: [
            {
              id: 'producto-x',
              totalPrice: precioDelProducto,
              assignment: { type: 'one', participants: { p2: 1 } },
            },
            {
              id: 'resto',
              totalPrice: 1346,
              assignment: { type: 'one', participants: { p1: 1 } },
            },
          ],
        },
      ],
    },
  ],
  settlements: [],
});

test('A11c el total pagado NO cambia al corregir una línea: solo cambia el '
    + 'reparto de ESE total', () => {
  const antes = computeAggregates(ticketDe1596(200));
  const despues = computeAggregates(ticketDe1596(250));

  // El gasto de la sesión es el mismo antes y después: 15,96 €.
  assert.equal(antes.sessionTotals.grandTotal, 1596);
  assert.equal(despues.sessionTotals.grandTotal, 1596);
  // Y lo repartido sigue sumando exactamente el total, nunca más.
  for (const r of [antes, despues]) {
    assert.equal(r.balances.p1.consumed + r.balances.p2.consumed, 1596);
  }
  // Lo que cambia es el peso: Jorge asume un poco más y Alba un poco menos.
  assert.ok(despues.balances.p2.consumed > antes.balances.p2.consumed);
  assert.ok(despues.balances.p1.consumed < antes.balances.p1.consumed);
});

test('A11c si la línea y el total estaban mal, corregir el total es otra '
    + 'decisión y ESA sí mueve el gasto', () => {
  const soloLinea = computeAggregates(ticketDe1596(250));
  const conTotalCorregido = ticketDe1596(250);
  conTotalCorregido.accounts[0].tickets[0].grandTotal = 1646;

  const r = computeAggregates(conTotalCorregido);

  assert.equal(soloLinea.sessionTotals.grandTotal, 1596);
  assert.equal(r.sessionTotals.grandTotal, 1646);
  assert.equal(r.balances.p1.consumed + r.balances.p2.consumed, 1646);
});

test('A11c un ticket cuya suma de líneas NO coincide con el total sigue '
    + 'repartiendo el total real (impuestos/propina)', () => {
  // Suma de líneas 1546 ≠ total 1596: los 50 céntimos de diferencia se
  // prorratean, que es justo el comportamiento de DC-11.
  const r = computeAggregates(ticketDe1596(200));

  assert.equal(r.balances.p1.consumed + r.balances.p2.consumed, 1596);
  assert.ok(r.balances.p2.consumed > 200); // su línea + su parte del extra
});

test('A11c retirar un producto inventado no devuelve dinero: el total real '
    + 'se reparte entre lo que queda', () => {
  const sinProducto = ticketDe1596(200);
  sinProducto.accounts[0].tickets[0].lines =
    sinProducto.accounts[0].tickets[0].lines.filter((l) => l.id === 'resto');

  const r = computeAggregates(sinProducto);

  assert.equal(r.sessionTotals.grandTotal, 1596);
  assert.equal(r.balances.p1.consumed, 1596);
  assert.equal(r.balances.p2.consumed, 0);
});

test('A11c corregir la línea con un pago previo: el pago sobrevive y la '
    + 'diferencia sale del reparto, no de un total inventado', () => {
  const conPago = ticketDe1596(250);
  conPago.externalConfirmed = [{ from: 'p2', to: 'p1', amount: 200 }];

  const r = computeAggregates(conPago);

  assert.equal(r.sessionTotals.grandTotal, 1596);
  assert.equal(r.sessionTotals.settledConfirmed, 200);
  // Jorge debe su consumo recalculado menos lo que ya pagó.
  assert.equal(r.balances.p2.outstanding, 200 - r.balances.p2.consumed);
});

test('A11c podar una unidad deja el consumo SOLO en quien conserva la suya',
    () => {
  // «2 × Coca-Cola»: u0 de Alba, u1 de Jorge. El admin baja a 1 unidad y la
  // app poda u1. Nadie hereda esa unidad: el consumo de Jorge desaparece y
  // el precio corregido recae en quien sigue teniendo la suya.
  const antes = gasto(300);
  antes.accounts[0].tickets[0].lines = [
    {
      id: 'l1',
      totalPrice: 300,
      quantityMilli: 2000,
      assignment: {
        type: 'units',
        schemaVersion: 2,
        units: { u0: { p1: true }, u1: { p2: true } },
      },
    },
  ];
  const despues = structuredClone(antes);
  despues.accounts[0].tickets[0].grandTotal = 150;
  despues.accounts[0].tickets[0].lines = [
    {
      id: 'l1',
      totalPrice: 150,
      quantityMilli: 1000,
      assignment: {
        type: 'units',
        schemaVersion: 2,
        units: { u0: { p1: true } },
      },
    },
  ];

  assert.equal(computeAggregates(antes).balances.p2.consumed, 150);
  const r = computeAggregates(despues);
  assert.equal(r.balances.p2.consumed, 0);
  assert.equal(r.balances.p1.consumed, 150);
});
