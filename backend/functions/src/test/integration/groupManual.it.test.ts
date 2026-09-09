/**
 * BUG-6: un GRUPO de una cuenta y una persona sin app reparte igual que
 * cualquier otro. La app lo bloqueaba por contar membresias; aqui se
 * comprueba que el backend nunca tuvo ese problema y que el ciclo economico
 * completo —reparto, balances, liquidacion y obligacion— sale con recompute
 * REAL, no con datos inyectados.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { recomputeSession } from '../../recompute.js';
import { clearFirestore, db, disposeApp, emulatorAvailable } from './harness.js';

const EDGAR = 'uid-edgar';
const PABLO_UID = 'uid-pablo';
const GRUPO = 'grupo-piso';
const MANUAL = 'manual-pablo';

describe('grupo ACCOUNT + MANUAL (BUG-6)', { skip: !emulatorAvailable() }, () => {
  before(() => {
    process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda';
  });
  after(disposeApp);
  beforeEach(clearFirestore);

  /** 1) grupo con UN propietario  ·  2) se le añade un MANUAL. */
  async function seedGroup(): Promise<void> {
    const f = db();
    await f.doc(`spaces/${GRUPO}`).set({
      name: 'Piso', ownerUid: EDGAR, kind: 'group',
      status: 'active', schemaVersion: 2,
    });
    await f.doc(`spaces/${GRUPO}/members/${EDGAR}`).set({ uid: EDGAR });
    await f.doc(`spaces/${GRUPO}/manualParticipants/${MANUAL}`).set({
      manualId: MANUAL, displayName: 'Pablo', linkedUid: null,
      createdByUid: EDGAR, schemaVersion: 1,
    });
    await f.doc(`profiles/${EDGAR}`).set({ displayName: 'Edgar' });
  }

  /** 3) ticket entre ambos: pago yo 30 €, 10 mios y 20 de Pablo. */
  async function seedTicket(): Promise<void> {
    const f = db();
    await f.doc('sessions/s1').set({
      ownerUid: EDGAR, kind: 'single', status: 'open',
      splitModeDefault: 'byItem', currency: 'EUR', spaceId: GRUPO,
      computeVersion: 0, totals: {}, balances: {},
    });
    await f.doc('sessions/s1/participants/p1').set({
      name: 'Edgar', isOwner: true, order: 0, active: true,
      claimedByDevice: EDGAR,
    });
    await f.doc('sessions/s1/participants/p2').set({
      name: 'Pablo', isOwner: false, order: 1, active: true,
      claimedByDevice: '', manualId: MANUAL,
    });
    await f.doc('sessions/s1/accounts/a1').set({ name: 'Compra', totals: {} });
    await f.doc('sessions/s1/accounts/a1/tickets/t1').set({
      kind: 'manual', grandTotal: 3000, paidByParticipantId: 'p1',
      merchant: { name: 'Super' }, spaceId: GRUPO,
    });
    await f.doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').set({
      name: 'Lo mio', totalPrice: 1000, order: 0,
      assignment: { type: 'one', participants: { p1: 1 } },
    });
    await f.doc('sessions/s1/accounts/a1/tickets/t1/lines/l2').set({
      name: 'Lo de Pablo', totalPrice: 2000, order: 1,
      assignment: { type: 'one', participants: { p2: 1 } },
    });
  }

  const entries = async (): Promise<
    Array<{ id: string } & FirebaseFirestore.DocumentData>
  > =>
    (await db().collection('economicEntries').get()).docs.map((d) => ({
      id: d.id, ...d.data(),
    }));

  it('ciclo completo: reparto, balances, liquidacion y obligacion', async () => {
    await seedGroup();
    await seedTicket();

    // 4) recompute REAL.
    await recomputeSession('s1');

    // 5) dos identidades economicas, ni una mas.
    const session = (await db().doc('sessions/s1').get()).data()!;
    const balances = session.balances as Record<string, { net: number }>;
    assert.deepEqual(Object.keys(balances).sort(), ['p1', 'p2']);
    assert.equal(session.totals.grandTotal, 3000);
    // Pague 3000 y consumi 1000 → me deben 2000. Pablo consumio 2000.
    assert.equal(balances.p1.net, 2000);
    assert.equal(balances.p2.net, -2000);

    const settlements =
      (await db().collection('sessions/s1/settlements').get()).docs;
    assert.equal(settlements.length, 1);
    assert.equal(settlements[0].data().from, 'p2');
    assert.equal(settlements[0].data().to, 'p1');
    assert.equal(settlements[0].data().amount, 2000);

    // La obligacion se expresa con el actor MANUAL y solo yo puedo leerla:
    // Pablo no tiene UID con el que leer nada.
    const [entry] = await entries();
    assert.equal(entry.debtorUid, `manual:${MANUAL}`);
    assert.equal(entry.creditorUid, EDGAR);
    assert.equal(entry.amount, 2000);
    assert.deepEqual(entry.memberUids, [EDGAR]);
  });

  it('editar el ticket recalcula sin cambiar de actor', async () => {
    await seedGroup();
    await seedTicket();
    await recomputeSession('s1');
    const antes = await entries();

    // Pablo consumio menos de lo apuntado.
    await db().doc('sessions/s1/accounts/a1/tickets/t1/lines/l2').update({
      totalPrice: 1000,
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t1').update({
      grandTotal: 2000,
    });
    await recomputeSession('s1');

    const despues = await entries();
    assert.equal(despues.length, 1);
    assert.equal(despues[0].id, antes[0].id, 'mismo documento');
    assert.equal(despues[0].amount, 1000);
    assert.equal(despues[0].debtorUid, `manual:${MANUAL}`,
      'el actor historico no se reescribe al editar');
  });

  it('reparto a partes iguales entre cuenta y MANUAL', async () => {
    await seedGroup();
    await seedTicket();
    // Ambos consumen la misma linea: mitad y mitad.
    await db().doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').update({
      assignment: { type: 'all' },
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t1/lines/l2').update({
      assignment: { type: 'all' },
    });
    await recomputeSession('s1');

    const session = (await db().doc('sessions/s1').get()).data()!;
    const balances = session.balances as Record<string, { net: number }>;
    // 3000 a partes iguales: 1500 cada uno. Pague yo → me debe 1500.
    assert.equal(balances.p1.net, 1500);
    assert.equal(balances.p2.net, -1500);
  });

  it('un MANUAL puede ser el PAGADOR', async () => {
    await seedGroup();
    await seedTicket();
    await db().doc('sessions/s1/accounts/a1/tickets/t1').update({
      paidByParticipantId: 'p2',
    });
    await recomputeSession('s1');

    const session = (await db().doc('sessions/s1').get()).data()!;
    const balances = session.balances as Record<string, { net: number }>;
    // Paga Pablo 3000 y consume 2000 → le deben 1000.
    assert.equal(balances.p2.net, 1000);
    assert.equal(balances.p1.net, -1000);

    const [entry] = await entries();
    assert.equal(entry.creditorUid, `manual:${MANUAL}`);
    assert.equal(entry.debtorUid, EDGAR);
    // Solo hay un lector: yo. Pablo no tiene con que leer.
    assert.deepEqual(entry.memberUids, [EDGAR]);
  });

  it('vinculado despues: ni deuda consigo mismo ni tercera identidad', async () => {
    await seedGroup();
    await seedTicket();
    // Pablo se registra, se vincula y ademas entra en el grupo con su cuenta.
    await db().doc(`spaces/${GRUPO}/members/${PABLO_UID}`).set({
      uid: PABLO_UID,
    });
    await db().doc(`spaces/${GRUPO}/manualParticipants/${MANUAL}`).update({
      linkedUid: PABLO_UID, linkStatus: 'active',
    });
    await db().doc(`profiles/${PABLO_UID}`).set({ displayName: 'Pablo' });
    // Y participa TAMBIEN con su cuenta en el mismo ticket.
    await db().doc('sessions/s1/participants/p3').set({
      name: 'Pablo (cuenta)', isOwner: false, order: 2, active: true,
      claimedByDevice: PABLO_UID,
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t1/lines/l3').set({
      name: 'Lo de su cuenta', totalPrice: 500, order: 2,
      assignment: { type: 'one', participants: { p3: 1 } },
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t1').update({
      grandTotal: 3500,
    });
    await recomputeSession('s1');

    for (const entry of await entries()) {
      const deudor = entry.debtorUid === `manual:${MANUAL}`
        ? PABLO_UID : entry.debtorUid;
      const acreedor = entry.creditorUid === `manual:${MANUAL}`
        ? PABLO_UID : entry.creditorUid;
      assert.notEqual(deudor, acreedor, `deuda consigo mismo en ${entry.id}`);
    }
    // Y ahora Pablo lee lo suyo, con el actor historico intacto.
    const manual = (await entries()).find(
      (e) => e.debtorUid === `manual:${MANUAL}`
        || e.creditorUid === `manual:${MANUAL}`,
    );
    assert.ok(manual, 'la obligacion del manual sigue existiendo');
    assert.ok((manual.memberUids as string[]).includes(PABLO_UID));
  });

  it('un MANUAL AJENO no da acceso a nadie de su espacio', async () => {
    await seedGroup();
    await seedTicket();
    // Otro espacio, con su propio manual ya vinculado a una cuenta.
    await db().doc('spaces/otro/manualParticipants/manual-ajeno').set({
      manualId: 'manual-ajeno', displayName: 'Ajeno',
      linkedUid: 'uid-intruso', createdByUid: 'uid-otro', schemaVersion: 1,
    });
    // El propietario de ESTA sesion apunta al manual de otro espacio.
    await db().doc('sessions/s1/participants/p2').update({
      manualId: 'manual-ajeno',
    });
    await recomputeSession('s1');

    // recompute resuelve los alias contra el espacio de la SESION, asi que
    // el vinculo ajeno no existe aqui: el intruso no gana ningun lector.
    for (const entry of await entries()) {
      assert.ok(
        !(entry.memberUids as string[]).includes('uid-intruso'),
        `un manual ajeno no debe dar acceso (${entry.id})`,
      );
    }
  });
});
