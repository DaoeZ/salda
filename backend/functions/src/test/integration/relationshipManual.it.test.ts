/**
 * El caso de Pablo (BUG-2), extremo a extremo contra el emulador.
 *
 * Una relacion ACCOUNT + MANUAL debe comportarse como cualquier otra: se le
 * añaden tickets, se reparte, se calculan saldos y se liquida. Y cuando Pablo
 * se registre, la vinculacion del Sprint 6 debe darle acceso SIN mover el
 * historico. Esto lo prueba con recompute real, no con datos inyectados.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { propagateManualLink } from '../../manualLink.js';
import { recomputeSession } from '../../recompute.js';
import { clearFirestore, db, disposeApp, emulatorAvailable } from './harness.js';

const YO = 'uid-edgar';
const PABLO_UID = 'uid-pablo';
const REL = 'rel-con-pablo'; // id GENERADO: no deriva de dos UID
const MANUAL = 'manual-pablo';

describe('relacion ACCOUNT + MANUAL (BUG-2)', { skip: !emulatorAvailable() }, () => {
  before(() => {
    process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda';
  });
  after(disposeApp);
  beforeEach(clearFirestore);

  /** Relacion v3 + sesion con un ticket que pago yo y consumimos los dos. */
  async function seed(): Promise<void> {
    const f = db();
    await f.doc(`spaces/${REL}`).set({
      name: 'Pablo', ownerUid: YO, kind: 'relationship',
      relationshipUids: [YO], relationshipManualId: MANUAL,
      status: 'active', schemaVersion: 3,
    });
    await f.doc(`spaces/${REL}/members/${YO}`).set({ uid: YO });
    await f.doc(`spaces/${REL}/manualParticipants/${MANUAL}`).set({
      manualId: MANUAL, displayName: 'Pablo', linkedUid: null,
      createdByUid: YO, schemaVersion: 1,
    });
    await f.doc('profiles/' + YO).set({ displayName: 'Edgar' });

    await f.doc('sessions/s1').set({
      ownerUid: YO, kind: 'single', status: 'open',
      splitModeDefault: 'byItem', currency: 'EUR', spaceId: REL,
      computeVersion: 0, totals: {}, balances: {},
    });
    await f.doc('sessions/s1/participants/p1').set({
      name: 'Edgar', isOwner: true, order: 0, active: true,
      claimedByDevice: '',
    });
    // Pablo participa como MANUAL: sin UID, con identidad estable.
    await f.doc('sessions/s1/participants/p2').set({
      name: 'Pablo', isOwner: false, order: 1, active: true,
      claimedByDevice: '', manualId: MANUAL,
    });
    await f.doc('sessions/s1/accounts/a1').set({ name: 'Cena', totals: {} });
    await f.doc('sessions/s1/accounts/a1/tickets/t1').set({
      kind: 'manual', grandTotal: 3000, paidByParticipantId: 'p1',
      merchant: { name: 'Cena' }, spaceId: REL,
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

  it('se reparte, se calculan saldos y se genera la liquidacion', async () => {
    await seed();
    await recomputeSession('s1');

    const session = (await db().doc('sessions/s1').get()).data()!;
    // Dos identidades economicas, ni una mas.
    const balances = session.balances as Record<string, { net: number }>;
    assert.deepEqual(Object.keys(balances).sort(), ['p1', 'p2']);
    // Yo pague 3000 y consumi 1000: me deben 2000. Pablo consumio 2000.
    assert.equal(balances.p1.net, 2000);
    assert.equal(balances.p2.net, -2000);
    assert.equal(session.totals.grandTotal, 3000);

    // Liquidacion generada: Pablo -> yo.
    const settlements =
      (await db().collection('sessions/s1/settlements').get()).docs;
    assert.equal(settlements.length, 1);
    assert.equal(settlements[0].data().from, 'p2');
    assert.equal(settlements[0].data().to, 'p1');
    assert.equal(settlements[0].data().amount, 2000);

    // Y la obligacion se expresa con el actor manual, no con un UID.
    const [entry] = await entries();
    assert.equal(entry.debtorUid, `manual:${MANUAL}`);
    assert.equal(entry.creditorUid, YO);
    assert.equal(entry.amount, 2000);
    assert.deepEqual(entry.memberUids, [YO]);
  });

  it('al VINCULAR a Pablo conserva el historico y le da acceso', async () => {
    await seed();
    await recomputeSession('s1');
    const antes = await entries();
    const idAntes = antes[0].id;

    // Pablo se registra y el anfitrion aprueba (Sprint 6, ADR-037).
    const f = db();
    const batch = f.batch();
    batch.set(f.doc(`spaces/${REL}/manualLinkRequests/${MANUAL}_${PABLO_UID}`), {
      manualId: MANUAL, uid: PABLO_UID, displayName: 'Pablo',
      spaceOwnerUid: YO, status: 'accepted', attempt: 1, schemaVersion: 1,
    });
    batch.set(f.doc(`spaces/${REL}/linkedIdentities/${PABLO_UID}`), {
      uid: PABLO_UID, manualId: MANUAL, schemaVersion: 1,
    });
    batch.update(f.doc(`spaces/${REL}/manualParticipants/${MANUAL}`), {
      linkedUid: PABLO_UID,
    });
    await batch.commit();

    const result = await propagateManualLink(REL, MANUAL);
    assert.equal(result.status, 'active');

    const despues = await entries();
    // MISMO documento, MISMO importe, MISMO actor historico.
    assert.equal(despues.length, 1);
    assert.equal(despues[0].id, idAntes);
    assert.equal(despues[0].amount, antes[0].amount);
    assert.equal(despues[0].debtorUid, `manual:${MANUAL}`,
      'el actor economico NO se migra');
    // Y ahora Pablo puede leer lo suyo.
    assert.deepEqual(
      [...(despues[0].memberUids as string[])].sort(),
      [PABLO_UID, YO].sort(),
    );
  });

  it('vinculado, NO aparece una deuda de Pablo consigo mismo', async () => {
    await seed();
    // Caso limite: Pablo tambien tiene una cuenta participando en la sesion.
    await db().doc('sessions/s1/participants/p3').set({
      name: 'Pablo cuenta', isOwner: false, order: 2, active: true,
      claimedByDevice: PABLO_UID,
    });
    await db().doc('profiles/' + PABLO_UID).set({ displayName: 'Pablo' });
    await db().doc('sessions/s1/accounts/a1/tickets/t1/lines/l3').set({
      name: 'Lo de su cuenta', totalPrice: 500, order: 2,
      assignment: { type: 'one', participants: { p3: 1 } },
    });
    await db().doc('sessions/s1/accounts/a1/tickets/t1').update({
      grandTotal: 3500,
    });
    await db().doc(`spaces/${REL}/manualParticipants/${MANUAL}`).update({
      linkedUid: PABLO_UID,
    });
    await recomputeSession('s1');

    for (const entry of await entries()) {
      const deudor = entry.debtorUid === `manual:${MANUAL}`
        ? PABLO_UID : entry.debtorUid;
      const acreedor = entry.creditorUid === `manual:${MANUAL}`
        ? PABLO_UID : entry.creditorUid;
      assert.notEqual(deudor, acreedor, `self-debt en ${entry.id}`);
    }
  });
});
