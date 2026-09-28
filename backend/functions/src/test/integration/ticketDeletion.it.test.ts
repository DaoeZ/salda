/**
 * A2 — eliminar un gasto, contra Firestore real (emulador).
 *
 * Fija dos cosas que la función pura no puede demostrar:
 *
 *  1. EL DINERO. Al borrar el gasto desaparece su obligación, pero NO los
 *     pagos: un pago confirmado que ya no tiene deuda detrás se convierte en
 *     crédito del pagador, y el saldo puede invertirse. Una declaración sin
 *     confirmar sobrevive tal cual y sigue siendo confirmable después.
 *  2. LOS DATOS. El borrado del documento deja líneas huérfanas, un
 *     «documento fantasma» y accesos sin objeto; la purga los retira sin
 *     tocar nada ajeno, y repetirla no cambia el resultado.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { getStorage } from 'firebase-admin/storage';

import { purgeDeletedTicket } from '../../cleanup.js';
import { computeEconomicLedger } from '../../domain/economicLedger.js';
import { recomputeSession } from '../../recompute.js';
import {
  clearFirestore,
  db,
  disposeApp,
  emulatorAvailable,
  storageEmulatorAvailable,
} from './harness.js';

const ALBA = 'uid-alba'; // dueña de la sesión y acreedora
const JORGE = 'uid-jorge'; // deudor
const GRUPO = 'grupo-piso';

const T1 = 'sessions/s1/accounts/a1/tickets/t1';
const T2 = 'sessions/s1/accounts/a2/tickets/t2';

/** Sesión de grupo: Alba paga 20 € que consume Jorge. */
async function seed(): Promise<void> {
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
    ownerUid: ALBA, kind: 'single', status: 'open',
    splitModeDefault: 'byItem', currency: 'EUR', spaceId: GRUPO,
    contextModelVersion: 1, computeVersion: 0, totals: {}, balances: {},
  });
  await f.doc('sessions/s1/participants/p1').set({
    name: 'Alba', isOwner: true, order: 0, active: true, claimedByDevice: '',
  });
  await f.doc('sessions/s1/participants/p2').set({
    name: 'Jorge', isOwner: false, order: 1, active: true,
    claimedByDevice: JORGE,
  });
  await f.doc('sessions/s1/accounts/a1').set({ name: 'Súper', totals: {} });
  await f.doc(T1).set({
    kind: 'manual', grandTotal: 2000, paidByParticipantId: 'p1',
    merchant: { name: 'Súper' }, spaceId: GRUPO,
    imagePath: 'receipts/s1/t1/original.jpg',
  });
  await f.doc(`${T1}/lines/l1`).set({
    name: 'Lo de Jorge', totalPrice: 2000, order: 0,
    assignment: { type: 'one', participants: { p2: 1 } },
  });
}

/** Segundo gasto entre las mismas personas, en su propia cuenta. */
async function seedSegundo(): Promise<void> {
  const f = db();
  await f.doc('sessions/s1/accounts/a2').set({ name: 'Bar', totals: {} });
  await f.doc(T2).set({
    kind: 'manual', grandTotal: 500, paidByParticipantId: 'p1',
    merchant: { name: 'Bar' }, spaceId: GRUPO,
  });
  await f.doc(`${T2}/lines/l1`).set({
    name: 'Caña', totalPrice: 500, order: 0,
    assignment: { type: 'one', participants: { p2: 1 } },
  });
}

/** Pago humano con la forma que escribe `createEconomicPayment`. */
async function pago(
  id: string,
  amount: number,
  status: 'pending' | 'confirmed',
  allocations: Record<string, number>,
): Promise<void> {
  await db().doc(`economicPayments/${id}`).set({
    memberUids: [ALBA, JORGE].sort(),
    pairId: [ALBA, JORGE].sort().join('_'),
    payerUid: JORGE, receiverUid: ALBA, amount, currency: 'EUR',
    status, source: 'user', createdByUid: JORGE,
    allocations, sessionIds: ['s1'], schemaVersion: 1,
  });
}

const entradas = async () =>
  (await db().collection('economicEntries').get()).docs;

/**
 * Borrado tal y como lo hace la app: evidencia + delete, y después la purga
 * (que en producción dispara el trigger `cleanupOnTicketDelete`).
 */
async function eliminar(
  { sid = 's1', aid = 'a1', tid = 't1', actor = ALBA } = {},
): Promise<void> {
  const f = db();
  const ticket = await f.doc(`sessions/${sid}/accounts/${aid}/tickets/${tid}`)
    .get();
  const batch = f.batch();
  batch.set(f.doc(`sessions/${sid}/ticketRemovals/${tid}`), {
    ticketId: tid, accountId: aid,
    merchantName: (ticket.data()?.merchant as { name?: string })?.name ?? '',
    grandTotal: ticket.data()?.grandTotal ?? 0,
    removedBy: actor, removedAt: new Date(), schemaVersion: 1,
  });
  batch.delete(f.doc(`sessions/${sid}/accounts/${aid}/tickets/${tid}`));
  await batch.commit();
  await recomputeSession(sid);
  await purgeDeletedTicket(sid, aid, tid);
}

/**
 * Saldo bilateral firmado tal y como lo calcula la app: `> 0` significa que
 * ALBA debe a Jorge. Se computa con el MISMO motor que usa el ledger.
 */
async function saldo(): Promise<{ firmado: number; pendiente: number }> {
  const es = await entradas();
  const ps = (await db().collection('economicPayments').get()).docs;
  const [balance] = computeEconomicLedger({
    obligations: es.map((d) => ({
      id: d.id,
      debtorUid: d.data().debtorUid as string,
      creditorUid: d.data().creditorUid as string,
      amount: d.data().amount as number,
      currency: 'EUR',
    })),
    payments: ps.map((d) => ({
      id: d.id,
      payerUid: d.data().payerUid as string,
      receiverUid: d.data().receiverUid as string,
      amount: d.data().amount as number,
      currency: 'EUR',
      status: d.data().status as 'pending' | 'confirmed' | 'cancelled',
    })),
  });
  if (!balance) return { firmado: 0, pendiente: 0 };
  // firstUid es el menor alfabéticamente: 'uid-alba' < 'uid-jorge'.
  return {
    firmado: balance.originalFirstToSecond - balance.originalSecondToFirst -
      balance.confirmedFirstToSecond + balance.confirmedSecondToFirst,
    pendiente: balance.pendingSecondToFirst,
  };
}

describe('A2: eliminar un gasto', { skip: !emulatorAvailable() }, () => {
  before(() => { process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda'; });
  after(disposeApp);
  beforeEach(clearFirestore);

  it('CASO A: sin pagos, el gasto deja de existir y no queda saldo',
    async () => {
      await seed();
      await recomputeSession('s1');
      assert.equal((await entradas()).length, 1);

      await eliminar();

      assert.equal((await entradas()).length, 0);
      assert.deepEqual(await saldo(), { firmado: 0, pendiente: 0 });
      const sesion = await db().doc('sessions/s1').get();
      assert.equal((sesion.data()?.totals as { grandTotal: number }).grandTotal,
        0);
      assert.equal(
        (await db().collection('sessions/s1/settlements').get()).size, 0);
    });

  it('CASO B: un pago confirmado parcial sobrevive e invierte el saldo',
    async () => {
      await seed();
      await recomputeSession('s1');
      const entryId = (await entradas())[0].id;
      await pago('pay-b', 1000, 'confirmed', { [entryId]: 1000 });
      await recomputeSession('s1');
      assert.equal((await saldo()).firmado, -1000); // Jorge debe 10 €

      await eliminar();

      // Alba pasa a deber los 10 € que Jorge ya había pagado.
      assert.equal((await saldo()).firmado, 1000);
      const p = await db().doc('economicPayments/pay-b').get();
      assert.ok(p.exists, 'el pago no puede desaparecer');
      assert.equal(p.data()?.status, 'confirmed');
    });

  it('CASO C: un pago confirmado completo deja el crédito entero invertido',
    async () => {
      await seed();
      await recomputeSession('s1');
      const entryId = (await entradas())[0].id;
      await pago('pay-c', 2000, 'confirmed', { [entryId]: 2000 });
      await recomputeSession('s1');
      assert.equal((await saldo()).firmado, 0);

      await eliminar();

      assert.equal((await saldo()).firmado, 2000); // Alba debe 20 € a Jorge
    });

  it('CASO D: una declaración pendiente sobrevive y sigue siendo confirmable',
    async () => {
      await seed();
      await recomputeSession('s1');
      const entryId = (await entradas())[0].id;
      await pago('pay-d', 2000, 'pending', { [entryId]: 2000 });
      await recomputeSession('s1');

      await eliminar();

      // La obligación desaparece; la declaración NO se cancela ni se
      // convierte en pago: sigue esperando a quien tiene que confirmarla.
      const tras = await saldo();
      assert.equal(tras.firmado, 0);
      assert.equal(tras.pendiente, 2000);
      const p = await db().doc('economicPayments/pay-d').get();
      assert.equal(p.data()?.status, 'pending');

      // Y si el receptor la confirma después, el dinero cuenta como recibido.
      await db().doc('economicPayments/pay-d').update({ status: 'confirmed' });
      assert.equal((await saldo()).firmado, 2000);
    });

  it('CASO E: borrar uno de dos gastos no toca el otro ni reasigna el pago',
    async () => {
      await seed();
      await seedSegundo();
      await recomputeSession('s1');
      const grande = (await entradas())
        .find((d) => d.data().amount === 2000)!;
      const pequena = (await entradas())
        .find((d) => d.data().amount === 500)!;
      await pago('pay-e', 1000, 'confirmed', { [grande.id]: 1000 });
      await recomputeSession('s1');
      assert.equal((await saldo()).firmado, -1500);

      await eliminar(); // solo el de 20 €

      const restantes = await entradas();
      assert.equal(restantes.length, 1);
      assert.equal(restantes[0].id, pequena.id);
      // 5 € de deuda viva menos 10 € ya pagados: Alba debe 5 €.
      assert.equal((await saldo()).firmado, 500);
      // El pago NO se reasigna a la deuda que queda: su contexto es suyo.
      const p = await db().doc('economicPayments/pay-e').get();
      assert.deepEqual(Object.keys(p.data()?.allocations ?? {}), [grande.id]);
      // Y el otro gasto sigue entero, con su cuenta y su línea.
      assert.ok((await db().doc(T2).get()).exists);
      assert.equal((await db().collection(`${T2}/lines`).get()).size, 1);
      assert.ok((await db().doc('sessions/s1/accounts/a2').get()).exists);
    });

  it('recomputes repetidos convergen: el estado final no cambia', async () => {
    await seed();
    await recomputeSession('s1');
    const entryId = (await entradas())[0].id;
    await pago('pay-conv', 1000, 'confirmed', { [entryId]: 1000 });
    await recomputeSession('s1');

    await eliminar();
    const foto = async () => JSON.stringify({
      totals: (await db().doc('sessions/s1').get()).data()?.totals,
      settlements: (await db().collection('sessions/s1/settlements').get())
        .docs.map((d) => d.data()),
      entries: (await entradas()).length,
      saldo: await saldo(),
    });
    const primera = await foto();
    await recomputeSession('s1');
    await recomputeSession('s1');
    assert.equal(await foto(), primera);
    // Y el estado al que converge no deja ninguna liquidación fantasma sobre
    // la que se pueda actuar.
    assert.equal(
      (await db().collection('sessions/s1/settlements').get()).size, 0);
  });

  it('la purga retira lo derivado del ticket y nada más', async () => {
    await seed();
    await seedSegundo();
    await recomputeSession('s1');
    const f = db();
    // Accesos y enlaces vivos de AMBOS tickets.
    for (const tid of ['t1', 't2']) {
      await f.doc(`ticketLinks/tok-${tid}`).set({
        sessionId: 's1', accountId: tid === 't1' ? 'a1' : 'a2', ticketId: tid,
        merchantName: 'X', targetPid: 'p2', targetManualId: 'm1',
        createdByUid: ALBA, status: 'active', schemaVersion: 2,
      });
      await f.doc(`sessions/s1/ticketAccess/${tid}_${JORGE}`).set({
        uid: JORGE, token: `tok-${tid}`, ticketId: tid, pid: 'p2',
        schemaVersion: 1,
      });
      await f.doc(`sessions/s1/ticketClaims/${tid}_m1`).set({
        uid: JORGE, ticketId: tid, manualId: 'm1', schemaVersion: 1,
      });
    }
    assert.ok((await f.doc(`sessions/s1/ticketEntitlements/t1_${JORGE}`).get())
      .exists);

    await eliminar();

    // Del ticket borrado no queda nada, ni siquiera el fantasma que deja una
    // subcolección viva.
    assert.equal((await f.collection(`${T1}/lines`).get()).size, 0);
    assert.equal(
      (await f.collection('sessions/s1/accounts/a1/tickets').listDocuments())
        .length, 0);
    assert.ok(!(await f.doc('sessions/s1/accounts/a1').get()).exists,
      'la cuenta vacía debía retirarse');
    assert.ok(!(await f.doc(`sessions/s1/ticketEntitlements/t1_${JORGE}`).get())
      .exists);
    assert.ok(!(await f.doc(`sessions/s1/ticketAccess/t1_${JORGE}`).get())
      .exists);
    assert.ok(!(await f.doc('sessions/s1/ticketClaims/t1_m1').get()).exists);
    assert.ok(!(await f.doc('ticketLinks/tok-t1').get()).exists);

    // Y lo del OTRO ticket sigue intacto, igual que la evidencia del borrado.
    assert.ok((await f.doc('ticketLinks/tok-t2').get()).exists);
    assert.ok((await f.doc(`sessions/s1/ticketAccess/t2_${JORGE}`).get())
      .exists);
    assert.ok((await f.doc('sessions/s1/ticketClaims/t2_m1').get()).exists);
    assert.ok((await f.doc(`sessions/s1/ticketEntitlements/t2_${JORGE}`).get())
      .exists);
    assert.ok((await f.doc('sessions/s1/ticketRemovals/t1').get()).exists);
    // La sesión NO se borra aunque se quede sin gastos: es otro lifecycle.
    assert.ok((await f.doc('sessions/s1').get()).exists);
  });

  it('la foto del gasto se borra con él, y la de otro ticket no',
    { skip: !storageEmulatorAvailable() }, async () => {
      await seed();
      await seedSegundo();
      await recomputeSession('s1');
      const bucket = getStorage().bucket();
      const borrada = bucket.file('receipts/s1/t1/original.jpg');
      const ajena = bucket.file('receipts/s1/t2/original.jpg');
      await borrada.save(Buffer.from('foto'), { contentType: 'image/jpeg' });
      await ajena.save(Buffer.from('foto'), { contentType: 'image/jpeg' });

      await eliminar();

      assert.equal((await borrada.exists())[0], false);
      assert.equal((await ajena.exists())[0], true);
    });

  it('la purga es idempotente: repetirla no rompe ni borra de más',
    async () => {
      await seed();
      await seedSegundo();
      await recomputeSession('s1');

      await eliminar();
      await purgeDeletedTicket('s1', 'a1', 't1');
      await purgeDeletedTicket('s1', 'a1', 't1');

      assert.ok((await db().doc(T2).get()).exists);
      assert.ok((await db().doc('sessions/s1/accounts/a2').get()).exists);
      assert.ok((await db().doc('sessions/s1/ticketRemovals/t1').get()).exists);
      assert.equal((await entradas()).length, 1);
    });

  it('una cuenta con OTRO ticket dentro no se retira', async () => {
    await seed();
    // Segundo ticket en la MISMA cuenta.
    await db().doc('sessions/s1/accounts/a1/tickets/t3').set({
      kind: 'manual', grandTotal: 300, paidByParticipantId: 'p1',
      merchant: { name: 'Kiosco' }, spaceId: GRUPO,
    });
    await recomputeSession('s1');

    await eliminar();

    assert.ok((await db().doc('sessions/s1/accounts/a1').get()).exists);
    assert.ok((await db().doc('sessions/s1/accounts/a1/tickets/t3').get())
      .exists);
  });
});
