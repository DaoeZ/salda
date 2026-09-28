/**
 * A19 contra Firestore real: el protocolo de cierre de consumo de extremo a
 * extremo, y la serialización de resultados que lo sostiene.
 *
 * Lo que prueban las pruebas puras es el cálculo; lo que se prueba aquí es
 * que el FLUJO real produce ese cálculo: que la huella se sella, que la
 * reapertura por topología llega a escribirse, y que un recompute obsoleto
 * no puede quedar como estado final.
 *
 * Ejecutar desde la raíz:
 *   firebase emulators:exec --only firestore --project demo-salda \
 *     "npm --prefix backend/functions run test:integration"
 */
import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';
import { FieldValue } from 'firebase-admin/firestore';

import { recomputeSession } from '../../recompute.js';
import { clearFirestore, db, emulatorAvailable } from './harness.js';

const ALBA = 'uid-alba';
const JORGE = 'uid-jorge';
const GRUPO = 'grupo-piso';
const TICKET = 'sessions/s1/accounts/a1/tickets/t1';
const LINEA = `${TICKET}/lines/l1`;
const UNIDADES = 6;

const unitIds = (n: number) => Array.from({ length: n }, (_, i) => `u${i}`);

/** Alba (p1) paga 60 € de 6 unidades. Jorge (p2) puede reclamarlas. */
async function sembrar({ protocolo = true } = {}): Promise<void> {
  const f = db();
  await f.doc(`spaces/${GRUPO}`).set({
    name: 'Piso', ownerUid: ALBA, kind: 'group', status: 'active',
    schemaVersion: 2,
  });
  for (const uid of [ALBA, JORGE]) {
    await f.doc(`spaces/${GRUPO}/members/${uid}`).set({ uid });
    await f.doc(`profiles/${uid}`).set({ displayName: uid });
  }
  await f.doc('sessions/s1').set({
    ownerUid: ALBA, kind: 'single', status: 'open', splitModeDefault: 'byItem',
    currency: 'EUR', spaceId: GRUPO, contextModelVersion: 1,
    computeVersion: 0, totals: {}, balances: {},
  });
  await f.doc('sessions/s1/participants/p1').set({
    name: 'Alba', isOwner: true, order: 0, active: true, claimedByDevice: ALBA,
  });
  await f.doc('sessions/s1/participants/p2').set({
    name: 'Jorge', isOwner: false, order: 1, active: true, claimedByDevice: JORGE,
  });
  await f.doc('sessions/s1/accounts/a1').set({ name: 'Cena' });
  await f.doc(TICKET).set({
    kind: 'manual', grandTotal: 6000, paidByParticipantId: 'p1',
    merchant: { name: 'Bar' }, spaceId: GRUPO, contextModelVersion: 1,
    splitModeOverride: 'byItem',
    ...(protocolo
      ? { pickingModelVersion: 1, picking: { open: { p1: true, p2: true } } }
      : {}),
  });
  await f.doc(LINEA).set({
    name: 'Cerveza', totalPrice: 6000, quantityMilli: UNIDADES * 1000, order: 0,
    unitIds: unitIds(UNIDADES),
    assignment: { type: 'units', schemaVersion: 2, units: {} },
  });
}

const marcar = (unit: string, pid: string) =>
  db().doc(LINEA).update({ [`assignment.units.${unit}.${pid}`]: true });

const desmarcar = (unit: string, pid: string) =>
  db().doc(LINEA).update({
    [`assignment.units.${unit}.${pid}`]: FieldValue.delete(),
  });

const cerrar = (pid: string) =>
  db().doc(TICKET).update({ [`picking.open.${pid}`]: FieldValue.delete() });

const reabrir = (pid: string) =>
  db().doc(TICKET).update({ [`picking.open.${pid}`]: true });

const sesion = async () => (await db().doc('sessions/s1').get()).data()!;
const ticket = async () => (await db().doc(TICKET).get()).data()!;
const liquidaciones = async () =>
  (await db().collection('sessions/s1/settlements').get()).docs;
const obligaciones = async () =>
  (await db().collection('economicEntries').get()).docs;
const pagos = async () =>
  (await db().collection('economicPayments').get()).docs;

/** Cierra el ticket con Jorge llevándose las 6 unidades, y lo cobra. */
async function cerrarYCobrar(): Promise<void> {
  for (const u of unitIds(UNIDADES)) await marcar(u, 'p2');
  await cerrar('p1');
  await cerrar('p2');
  await recomputeSession('s1');
  const [liq] = await liquidaciones();
  assert.equal(liq.data().amount, 6000);
  await liq.ref.update({ state: 'confirmed' });
  await recomputeSession('s1');
}

describe('A19 · cierre de consumo (integración)', { skip: !emulatorAvailable() }, () => {
  beforeEach(async () => {
    await clearFirestore();
    await sembrar();
  });

  it('un ticket abierto no genera economía firme, pero sí cuenta lo gastado',
    async () => {
      await marcar('u0', 'p2');
      await recomputeSession('s1');
      const s = await sesion();
      // Todo el mundo a cero: el ticket no ha aportado nada al libro. El
      // mapa nunca está vacío —`computeBalance` emite una entrada por
      // participante—, lo que importa es que no haya consumo ni pago.
      assert.equal(s.balances.p1.paid, 0);
      assert.equal(s.balances.p1.consumed, 0);
      assert.equal(s.balances.p2.consumed, 0);
      assert.equal((await liquidaciones()).length, 0);
      assert.equal((await obligaciones()).length, 0);
      assert.equal(s.totals.grandTotal, 6000);
      // La huella se sella en la primera pasada, sin reabrir nada.
      const t = await ticket();
      assert.equal(typeof t.picking.fingerprint, 'string');
      assert.deepEqual(t.picking.open, { p1: true, p2: true });
      assert.equal(t.picking.firmContribution, undefined);
    });

  it('al cerrar el último pendiente aparece la economía y se congela',
    async () => {
      await marcar('u0', 'p2');
      await cerrar('p1');
      await cerrar('p2');
      await recomputeSession('s1');
      const s = await sesion();
      assert.equal(s.balances.p2.consumed, 1000);
      assert.equal(s.balances.p1.consumed, 5000); // residual del pagador
      assert.equal((await obligaciones()).length, 1);
      const t = await ticket();
      assert.equal(t.picking.firmContribution.grandTotal, 6000);
      assert.equal(t.picking.firmContribution.consumption.p2, 1000);
    });

  it('un ticket abierto no bloquea la economía de los demás', async () => {
    // Segundo gasto, legacy (sin protocolo): debe repartirse con normalidad.
    await db().doc('sessions/s1/accounts/a1/tickets/t2').set({
      kind: 'manual', grandTotal: 2000, paidByParticipantId: 'p1',
      merchant: { name: 'Otro' }, spaceId: GRUPO, contextModelVersion: 1,
      splitModeOverride: 'byItem',
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t2/lines/l1').set({
      name: 'Café', totalPrice: 2000, quantityMilli: 1000, order: 0,
      unitIds: ['u0'],
      assignment: { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } },
    });
    await marcar('u0', 'p2');   // el ticket A19 sigue abierto
    await recomputeSession('s1');
    const s = await sesion();
    assert.equal(s.balances.p2.consumed, 2000);   // solo el legacy
    assert.equal(s.totals.grandTotal, 8000);      // lo gastado, los dos
  });

  // ── Reapertura ───────────────────────────────────────────────────────

  it('reabrir un ticket ya cobrado NO fabrica una deuda inversa', async () => {
    await cerrarYCobrar();
    // Jorge reabre y se queda con una sola unidad.
    await reabrir('p2');
    for (const u of unitIds(UNIDADES).slice(1)) await desmarcar(u, 'p2');
    await recomputeSession('s1');

    const s = await sesion();
    // La economía sigue siendo la del cierre.
    assert.equal(s.balances.p2.consumed, 6000);
    assert.equal(s.balances.p1.outstanding, 0);
    assert.equal(s.balances.p2.outstanding, 0);
    // Ninguna liquidación nueva: solo la confirmada de antes.
    const liq = await liquidaciones();
    assert.equal(liq.length, 1);
    assert.equal(liq[0].data().state, 'confirmed');
    assert.equal(s.pendingSettlements, 0);
    // La obligación no cambia mientras se edita.
    const ob = await obligaciones();
    assert.equal(ob.length, 1);
    assert.equal(ob[0].data().amount, 6000);
    // Y el pago confirmado sigue donde estaba.
    assert.equal(
      (await pagos()).filter((d) => d.data().status === 'confirmed').length, 1);
  });

  it('al volver a cerrar, la reconciliación la hace el modelo de siempre',
    async () => {
      await cerrarYCobrar();
      await reabrir('p2');
      for (const u of unitIds(UNIDADES).slice(1)) await desmarcar(u, 'p2');
      await recomputeSession('s1');
      await cerrar('p2');
      await recomputeSession('s1');

      const ob = await obligaciones();
      assert.equal(ob.length, 1);
      assert.equal(ob[0].data().amount, 1000);
      // Obligación final 10 € contra un pago confirmado de 60 €: Alba
      // devuelve 50 €, con las reglas económicas existentes.
      const liq = await liquidaciones();
      const inversa = liq.find((d) => d.data().state !== 'confirmed')!;
      assert.equal(inversa.data().from, 'p1');
      assert.equal(inversa.data().to, 'p2');
      assert.equal(inversa.data().amount, 5000);
      assert.ok(liq.some(
        (d) => d.data().state === 'confirmed' && d.data().amount === 6000));
    });

  it('ACTOR HISTÓRICO: el consumidor congelado pasa a active:false y la '
    + 'economía del cierre sigue cuadrando', async () => {
    await cerrarYCobrar();
    // Se reabre de verdad: p1, que sigue activo, vuelve a estar pendiente.
    await reabrir('p1');
    await reabrir('p2');
    await desmarcar('u5', 'p2');
    await db().doc('sessions/s1/participants/p2').update({ active: false });
    await recomputeSession('s1');   // no debe lanzar

    const s = await sesion();
    assert.equal(s.balances.p1.paid, 6000);
    assert.equal(s.balances.p1.consumed, 0);
    assert.equal(s.balances.p2.consumed, 6000);
    assert.equal(s.balances.p1.outstanding, 0);
    assert.equal(s.balances.p2.outstanding, 0);
    const liq = await liquidaciones();
    assert.equal(liq.length, 1);
    assert.equal(liq[0].data().state, 'confirmed');
    const ob = await obligaciones();
    assert.equal(ob.length, 1);
    assert.equal(ob[0].data().amount, 6000);
    assert.equal(
      (await pagos()).filter((d) => d.data().status === 'confirmed').length, 1);
  });

  // ── Topología ────────────────────────────────────────────────────────

  it('cambiar la topología reabre a TODOS los activos', async () => {
    await marcar('u0', 'p2');
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    assert.equal((await obligaciones()).length, 1);

    await db().doc(LINEA).update({
      quantityMilli: 3000, unitIds: unitIds(3),
    });
    await recomputeSession('s1');

    const t = await ticket();
    assert.deepEqual(t.picking.open, { p1: true, p2: true });
    // Y mientras esté reabierto, la economía es la congelada.
    assert.equal((await obligaciones())[0].data().amount, 1000);
  });

  it('cambiar el nombre o el precio NO reabre', async () => {
    await marcar('u0', 'p2');
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    await db().doc(LINEA).update({ name: 'Caña', totalPrice: 7000 });
    await recomputeSession('s1');
    const t = await ticket();
    assert.deepEqual(t.picking.open ?? {}, {});
    assert.equal((await obligaciones()).length, 1);
  });

  // ── Derecho histórico (A11d): A19 no lo toca ─────────────────────────

  const entitlements = async () =>
    (await db().collection('sessions/s1/ticketEntitlements').get())
      .docs.map((d) => d.data().uid).sort();

  it('el pagador tiene derecho histórico con el ticket todavía abierto',
    async () => {
      await recomputeSession('s1');
      assert.deepEqual(await entitlements(), [ALBA]);
    });

  it('quien consume de forma provisional también lo obtiene', async () => {
    await marcar('u0', 'p2');
    await recomputeSession('s1');
    assert.deepEqual(await entitlements(), [ALBA, JORGE].sort());
  });

  it('un entitlement existente SOBREVIVE a una reapertura', async () => {
    await marcar('u0', 'p2');
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    const antes = await entitlements();
    await reabrir('p2');
    await desmarcar('u0', 'p2');
    await recomputeSession('s1');
    assert.deepEqual(await entitlements(), antes);
  });

  it('la mera pertenencia al grupo no concede derecho histórico', async () => {
    await db().doc('sessions/s1/participants/p3').set({
      name: 'Edgar', isOwner: false, order: 2, active: true,
      claimedByDevice: 'uid-edgar',
    });
    await db().doc('profiles/uid-edgar').set({ displayName: 'Edgar' });
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    assert.ok(!(await entitlements()).includes('uid-edgar'));
  });

  // ── Serialización de resultados (CAS) ────────────────────────────────

  it('el batch lleva precondición: una lectura vieja no puede escribir',
    async () => {
      const ref = db().doc('sessions/s1');
      const vieja = (await ref.get()).updateTime;
      await ref.update({ updatedAt: FieldValue.serverTimestamp() });
      const batch = db().batch();
      batch.update(ref, { totals: { grandTotal: 1 } }, { lastUpdateTime: vieja });
      await assert.rejects(
        batch.commit(),
        (e: { code?: number }) => e.code === 9,
      );
    });

  it('un recompute obsoleto no puede borrar la economía firme', async () => {
    await marcar('u0', 'p2');
    // A empieza con el ticket TODAVÍA abierto y no termina.
    const lecturaVieja = recomputeSession('s1');
    // B: se cierra el reparto y se publica la economía firme.
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    await lecturaVieja;

    // Sea cual sea el orden de llegada, el estado final es el más reciente.
    const s = await sesion();
    assert.equal(s.balances.p2.consumed, 1000);
    assert.equal((await obligaciones()).length, 1);
  });

  it('tras un conflicto CAS el estado termina recalculado con datos frescos',
    async () => {
      await marcar('u0', 'p2');
      await cerrar('p1');
      await cerrar('p2');
      // Escritura ajena entre la lectura y el commit: el primer intento
      // aborta y el reintento relee.
      const ref = db().doc('sessions/s1');
      await ref.update({ updatedAt: FieldValue.serverTimestamp() });
      await recomputeSession('s1');
      const s = await sesion();
      assert.equal(s.balances.p2.consumed, 1000);
      assert.equal((await obligaciones()).length, 1);
    });

  it('recompute repetido sobre el mismo estado es idempotente', async () => {
    await marcar('u0', 'p2');
    await cerrar('p1');
    await cerrar('p2');
    await recomputeSession('s1');
    const v1 = (await sesion()).computeVersion;
    await recomputeSession('s1');
    assert.equal((await sesion()).computeVersion, v1);
  });
});
