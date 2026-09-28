/**
 * A11d — derecho histórico por ticket (proyección C).
 *
 * Es la hermana MONOTÓNICA de `ticketParticipants`: aquella es la foto del
 * reparto VIVO y retira a quien deja de consumir; esta constata que alguien
 * participó ALGUNA VEZ y no se retira nunca. Sin esa diferencia, una
 * corrección A11c posterior le arrancaría a un ex-miembro el ticket que
 * explica la deuda que ya pagó.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeAggregates, type SessionSnapshot } from '../recompute.js';

/** Sesión de grupo: dos identidades con cuenta y una persona sin ella. */
const conCuentas = (): SessionSnapshot => ({
  splitModeDefault: 'byItem',
  ownerUid: 'uid-alba',
  participants: [
    { id: 'p1', name: 'Alba', isOwner: true, order: 0 },
    { id: 'p2', name: 'Jorge', order: 1, userUid: 'uid-jorge' },
    { id: 'p3', name: 'Tete', order: 2, manualId: 'm-tete' },
  ],
  accounts: [
    {
      id: 'a1',
      tickets: [
        {
          id: 't1',
          grandTotal: 3000,
          paidByParticipantId: 'p1',
          lines: [
            { id: 'l1', totalPrice: 1000,
              assignment: { type: 'one', participants: { p2: 1 } } },
            { id: 'l2', totalPrice: 2000,
              assignment: { type: 'one', participants: { p3: 1 } } },
          ],
        },
      ],
    },
  ],
  settlements: [],
});

const derechosDe = (snapshot: SessionSnapshot, ticketId: string): string[] =>
  computeAggregates(snapshot)
    .ticketEntitlements.filter((entry) => entry.ticketId === ticketId)
    .map((entry) => entry.uid)
    .sort();

test('derecho histórico: lo obtiene quien consume y quien paga', () => {
  assert.deepEqual(derechosDe(conCuentas(), 't1'), ['uid-alba', 'uid-jorge']);
});

test('derecho histórico: un MANUAL sin cuenta no lo obtiene', () => {
  const derechos = computeAggregates(conCuentas()).ticketEntitlements;
  assert.ok(!derechos.some((entry) => entry.uid.startsWith('manual:')));
  assert.ok(!derechos.some((entry) => entry.uid === 'm-tete'));
});

test('derecho histórico: un MANUAL vinculado sí, con su UID real', () => {
  const snapshot = conCuentas();
  snapshot.manualAliases = { 'm-tete': 'uid-tete' };
  assert.deepEqual(
    derechosDe(snapshot, 't1'), ['uid-alba', 'uid-jorge', 'uid-tete']);
});

test('derecho histórico: lleva la cuenta, para llegar al ticket sin listar',
  () => {
    const derecho = computeAggregates(conCuentas())
      .ticketEntitlements.find((entry) => entry.uid === 'uid-jorge');
    assert.equal(derecho?.accountId, 'a1');
    assert.equal(derecho?.id, 't1_uid-jorge');
  });

test('derecho histórico: congela los nombres de ESE reparto', () => {
  // Sin ellos el reparto es ilegible para quien ya no puede leer los
  // participantes de la sesión; con el censo entero se le daría de más.
  const derecho = computeAggregates(conCuentas())
    .ticketEntitlements.find((entry) => entry.uid === 'uid-jorge');
  assert.deepEqual(derecho?.participantNames,
    { p1: 'Alba', p2: 'Jorge', p3: 'Tete', 'manual:m-tete': 'Tete' });
});

test('derecho histórico: el MANUAL también se nombra por su ACTOR', () => {
  // La deuda de P5 nombra a `manual:{id}`, no a un `pid`. Sin el alias, un
  // ex-miembro veía «Persona sin nombre» en su propio saldo, porque el
  // nombre de un manual lo custodia el espacio y ya no puede leerlo.
  const derecho = computeAggregates(conCuentas())
    .ticketEntitlements.find((entry) => entry.uid === 'uid-jorge');
  assert.equal(derecho?.participantNames['manual:m-tete'], 'Tete');
  // Una cuenta NO recibe alias: su nombre vive en el perfil público.
  assert.ok(!Object.keys(derecho?.participantNames ?? {})
    .some((key) => key.startsWith('manual:') && key !== 'manual:m-tete'));
});

test('derecho histórico: es idempotente entre recomputes', () => {
  assert.deepEqual(
    computeAggregates(conCuentas()).ticketEntitlements,
    computeAggregates(conCuentas()).ticketEntitlements,
  );
});

test('derecho histórico: solo el ticket en el que se participó', () => {
  const snapshot = conCuentas();
  snapshot.accounts[0].tickets.push({
    id: 't2',
    grandTotal: 500,
    paidByParticipantId: 'p1',
    lines: [
      { id: 'l1', totalPrice: 500,
        assignment: { type: 'one', participants: { p1: 1 } } },
    ],
  });
  assert.deepEqual(derechosDe(snapshot, 't2'), ['uid-alba']);
});

test('derecho histórico: ser miembro del grupo no basta', () => {
  // p4 está en la sesión pero no consume ni paga en t1.
  const snapshot = conCuentas();
  snapshot.participants.push(
    { id: 'p4', name: 'Marta', order: 3, userUid: 'uid-marta' });
  assert.ok(!derechosDe(snapshot, 't1').includes('uid-marta'));
});

// El caso que motivó la proyección: Jorge consume, lo expulsan y DESPUÉS un
// administrador corrige el ticket hasta que su consumo desaparece.
test('derecho histórico: una corrección A11c retira la economía, no el '
  + 'derecho ya concedido', () => {
  assert.ok(derechosDe(conCuentas(), 't1').includes('uid-jorge'));

  const corregido = conCuentas();
  corregido.accounts[0].tickets[0].lines.splice(0, 1);
  corregido.accounts[0].tickets[0].grandTotal = 2000;
  const despues = computeAggregates(corregido);

  // La foto del reparto vivo SÍ lo retira…
  assert.ok(!despues.ticketParticipants.some((entry) => entry.pid === 'p2'));
  // …y su obligación desaparece de la economía vigente…
  assert.ok(!despues.economicEntries.some(
    (entry) => entry.debtorUid === 'uid-jorge'));
  // …y el conjunto deseado deja de mencionarlo, que es exactamente por qué
  // `recomputeSession` NO puede tener un bucle de borrado para esta
  // colección: lo que no se menciona se queda como está, concedido.
  assert.ok(!despues.ticketEntitlements.some(
    (entry) => entry.uid === 'uid-jorge'));
});
