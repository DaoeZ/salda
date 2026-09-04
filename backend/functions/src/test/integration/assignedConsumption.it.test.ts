/**
 * A10 — el reparto que hace otra persona vale igual, contra Firestore real.
 *
 * Lo que se comprueba aquí no es la UI ni los permisos (eso son Rules), sino
 * lo único que de verdad importa después: que una asignación escrita por
 * quien administra el gasto produce EXACTAMENTE la misma economía que si la
 * hubiera hecho el propio beneficiario — incluida una persona sin cuenta,
 * que no puede entrar a reclamar nada.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { recomputeSession } from '../../recompute.js';
import { clearFirestore, db, disposeApp, emulatorAvailable } from './harness.js';

const ALBA = 'uid-alba'; // paga y administra
const JORGE = 'uid-jorge'; // consume, con cuenta
const GRUPO = 'grupo-piso';
const LINEA = 'sessions/s1/accounts/a1/tickets/t1/lines/l1';

/** Alba paga 20 € de dos unidades a 10 €; hay además una persona MANUAL. */
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
  await f.doc('sessions/s1/participants/p3').set({
    name: 'Tete', isOwner: false, order: 2, active: true,
    claimedByDevice: '', manualId: 'm-tete',
  });
  await f.doc('sessions/s1/accounts/a1').set({ name: 'Bar', totals: {} });
  await f.doc('sessions/s1/accounts/a1/tickets/t1').set({
    kind: 'manual', grandTotal: 2000, paidByParticipantId: 'p1',
    merchant: { name: 'Bar' }, spaceId: GRUPO,
  });
  await f.doc(LINEA).set({
    name: 'Cocacola', totalPrice: 2000, quantityMilli: 2000, order: 0,
    unitIds: ['u0', 'u1'],
    assignment: { type: 'units', schemaVersion: 2, units: {} },
  });
}

/** Lo que escribe A10: la asignación y quién la hizo. */
const asignar = (unidad: string, pid: string, actor = ALBA) =>
  db().doc(LINEA).update({
    [`assignment.units.${unidad}.${pid}`]: true,
    [`assignment.by.${unidad}.${pid}`]: actor,
  });

const deudaDe = async (uid: string) => {
  const entradas = await db().collection('economicEntries')
    .where('debtorUid', '==', uid).get();
  return entradas.docs.reduce((suma, d) => suma + (d.data().amount as number), 0);
};

const consumo = async (pid: string) => {
  const balances = (await db().doc('sessions/s1').get()).data()?.balances as
    Record<string, { consumed: number }>;
  return balances?.[pid]?.consumed ?? 0;
};

describe('A10: consumo asignado por otra persona', { skip: !emulatorAvailable() },
  () => {
    before(() => { process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda'; });
    after(disposeApp);
    beforeEach(clearFirestore);

    it('una unidad asignada a un tercero genera SU deuda, no la del actor',
      async () => {
        await seed();
        await asignar('u0', 'p2'); // Alba se lo asigna a Jorge
        await recomputeSession('s1');

        // 10 € de Jorge; la unidad sin reclamar recae en quien pagó.
        assert.equal(await consumo('p2'), 1000);
        assert.equal(await consumo('p1'), 1000);
        assert.equal(await deudaDe(JORGE), 1000);
        // La firma es metadata: no aparece en la economía ni la altera.
        assert.equal(await deudaDe(ALBA), 0);
      });

    it('una persona SIN cuenta recibe su obligación sin entrar a nada',
      async () => {
        await seed();
        await asignar('u0', 'p3'); // Tete, manual
        await asignar('u1', 'p2');
        await recomputeSession('s1');

        const entradas = await db().collection('economicEntries').get();
        const deTete = entradas.docs.find(
          (d) => d.data().debtorUid === 'manual:m-tete');
        assert.ok(deTete, 'la persona manual debe tener su obligación');
        assert.equal(deTete!.data().amount, 1000);
        assert.equal(deTete!.data().creditorUid, ALBA);
        assert.equal(await deudaDe(JORGE), 1000);
      });

    it('una unidad compartida se parte a medias entre cuenta y manual',
      async () => {
        await seed();
        await asignar('u0', 'p2');
        await asignar('u0', 'p3');
        await asignar('u1', 'p1'); // la otra se la queda quien pagó
        await recomputeSession('s1');

        assert.equal(await consumo('p2'), 500);
        assert.equal(await consumo('p3'), 500);
        assert.equal(await consumo('p1'), 1000);
        assert.equal(await deudaDe(JORGE), 500);
      });

    it('el resultado es idéntico si la asignación la hace el beneficiario',
      async () => {
        await seed();
        await asignar('u0', 'p2', JORGE); // se marca él mismo
        await recomputeSession('s1');
        const propio = await deudaDe(JORGE);

        await clearFirestore();
        await seed();
        await asignar('u0', 'p2', ALBA); // se lo asigna Alba
        await recomputeSession('s1');

        assert.equal(await deudaDe(JORGE), propio);
      });

    it('quitar la asignación devuelve la unidad a quien pagó', async () => {
      await seed();
      await asignar('u0', 'p2');
      await recomputeSession('s1');
      assert.equal(await deudaDe(JORGE), 1000);

      await db().doc(LINEA).update({
        'assignment.units.u0.p2': (await import('firebase-admin/firestore'))
          .FieldValue.delete(),
        'assignment.by.u0.p2': (await import('firebase-admin/firestore'))
          .FieldValue.delete(),
      });
      await recomputeSession('s1');

      assert.equal(await deudaDe(JORGE), 0);
      assert.equal(await consumo('p1'), 2000);
    });
  });
