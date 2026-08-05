/**
 * Prueba INTEGRADA del flujo real de vinculación (C1) contra el emulador.
 *
 * No inyecta `manualAliases` a mano: escribe los documentos que escribe la
 * app, ejecuta el mecanismo real y comprueba el efecto observable. Es la
 * prueba que faltaba y por la que C1 pasó desapercibido.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { FieldValue } from 'firebase-admin/firestore';

import {
  claimManualLinkPropagation,
  handleManualLinkWrite,
  propagateManualLink,
  publishManualLinkTerminal,
} from '../../manualLink.js';
import { recomputeSession } from '../../recompute.js';
import {
  clearFirestore,
  db,
  disposeApp,
  emulatorAvailable,
  waitFor,
} from './harness.js';

const OWNER = 'uid-anfitrion';
const MARTA = 'uid-marta';

describe('vinculación: efecto real (C1)', { skip: !emulatorAvailable() }, () => {
  before(() => {
    process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda';
  });
  after(disposeApp);
  beforeEach(clearFirestore);

  /** Sesión con economía previa: el anfitrión paga, un MANUAL consume. */
  async function seedSessionWithManual(sid: string): Promise<void> {
    const f = db();
    await f.doc(`spaces/sp1`).set({
      name: 'Piso', ownerUid: OWNER, status: 'active',
      kind: 'group', schemaVersion: 2,
    });
    await f.doc(`spaces/sp1/manualParticipants/m1`).set({
      manualId: 'm1', displayName: 'Marta', linkedUid: null,
      createdByUid: OWNER, schemaVersion: 1,
    });
    await f.doc(`sessions/${sid}`).set({
      ownerUid: OWNER, kind: 'single', status: 'open',
      splitModeDefault: 'byItem', currency: 'EUR', spaceId: 'sp1',
      computeVersion: 0, totals: {}, balances: {},
    });
    await f.doc(`sessions/${sid}/participants/p1`).set({
      name: 'Edgar', isOwner: true, order: 0, active: true,
      claimedByDevice: '',
    });
    await f.doc(`sessions/${sid}/participants/p2`).set({
      name: 'Marta', isOwner: false, order: 1, active: true,
      claimedByDevice: '', manualId: 'm1',
    });
    // El documento de la CUENTA debe existir explícitamente: escribir una
    // subcolección no materializa a su padre, y recompute lista `accounts`.
    await f.doc(`sessions/${sid}/accounts/a1`).set({
      name: 'Cena', totals: {},
    });
    await f.doc(`sessions/${sid}/accounts/a1/tickets/t1`).set({
      kind: 'manual', grandTotal: 2000, paidByParticipantId: 'p1',
      merchant: { name: 'Cena' }, spaceId: 'sp1',
    });
    await f.doc(`sessions/${sid}/accounts/a1/tickets/t1/lines/l1`).set({
      name: 'Lo de Edgar', totalPrice: 1000, order: 0,
      assignment: { type: 'one', participants: { p1: 1 } },
    });
    await f.doc(`sessions/${sid}/accounts/a1/tickets/t1/lines/l2`).set({
      name: 'Lo de Marta', totalPrice: 1000, order: 1,
      assignment: { type: 'one', participants: { p2: 1 } },
    });
    // Identidad registrada del anfitrión, para que resuelva a UID.
    await f.doc(`profiles/${OWNER}`).set({ displayName: 'Edgar' });
  }

  const entriesOf = async (): Promise<
    Array<{ id: string; data: FirebaseFirestore.DocumentData }>
  > => {
    const snap = await db().collection('economicEntries').get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  };

  it('la aprobación seguida de un rename tardío aún da acceso al histórico',
      async () => {
    await seedSessionWithManual('s1');
    await recomputeSession('s1');

    // ── Estado previo: la obligación existe y Marta NO puede leerla.
    const antes = await entriesOf();
    assert.equal(antes.length, 1, 'debe existir la obligación del manual');
    assert.deepEqual(antes[0].data.memberUids, [OWNER]);
    assert.equal(antes[0].data.debtorUid, 'manual:m1');
    const idAntes = antes[0].id;
    const importeAntes = antes[0].data.amount;

    // ── Aprobación: exactamente lo que escribe la app, en un batch.
    const f = db();
    const beforeApproval = await f.doc('spaces/sp1/manualParticipants/m1').get();
    const batch = f.batch();
    batch.set(f.doc('spaces/sp1/manualLinkRequests/m1_' + MARTA), {
      manualId: 'm1', uid: MARTA, displayName: 'Marta',
      status: 'accepted', schemaVersion: 1,
    });
    batch.set(f.doc(`spaces/sp1/linkedIdentities/${MARTA}`), {
      uid: MARTA, manualId: 'm1', schemaVersion: 1,
    });
    batch.update(f.doc('spaces/sp1/manualParticipants/m1'), {
      linkedUid: MARTA,
    });
    await batch.commit();

    const acceptedRequest = await f
      .doc('spaces/sp1/manualLinkRequests/m1_' + MARTA)
      .get();
    const approvedManual = await f
      .doc('spaces/sp1/manualParticipants/m1')
      .get();
    assert.equal(acceptedRequest.data()?.status, 'accepted');
    assert.equal(approvedManual.data()?.linkedUid, MARTA);
    assert.equal(approvedManual.data()?.linkStatus, undefined,
      'accepted + linkedUid no publica processing');
    await f.doc('spaces/sp1/manualParticipants/m1').update({
      displayName: 'Marta G.',
    });

    // ── C1 EN VIVO: con el vínculo ya escrito, y sin propagar, el acceso
    // NO existe. Esto es exactamente lo que ocurría antes de la corrección.
    const sinPropagar = await entriesOf();
    assert.deepEqual(
      sinPropagar[0].data.memberUids, [OWNER],
      'sin propagación el vínculo es inerte: ese era el defecto C1',
    );

    // ── Mecanismo real.
    await handleManualLinkWrite(
      'sp1',
      'm1',
      beforeApproval.data(),
      approvedManual,
    );

    // ── Efecto: Marta ya es lectora, sin haber tocado ningún ticket.
    const despues = await entriesOf();
    assert.equal(despues.length, 1);
    assert.deepEqual(
      [...despues[0].data.memberUids].sort(), [OWNER, MARTA].sort(),
    );
    // Y nada económico se ha movido.
    assert.equal(despues[0].id, idAntes, 'el id del documento no cambia');
    assert.equal(despues[0].data.amount, importeAntes);
    assert.equal(despues[0].data.debtorUid, 'manual:m1',
      'el actor economico sigue siendo el manual');
    assert.equal(despues[0].data.creditorUid, OWNER);

    // El estado del vínculo solo es `active` cuando la propagación terminó.
    const manual = await db().doc('spaces/sp1/manualParticipants/m1').get();
    assert.equal(manual.data()?.linkStatus, 'active');
  });

  it('la reclamación inicial escribe processing sin sembrarlo a mano',
      async () => {
    await seedSessionWithManual('s1');
    const ref = db().doc('spaces/sp1/manualParticipants/m1');
    await ref.update({
      linkedUid: MARTA,
      linkError: 'stale-error',
      linkBlockedSessions: 1,
    });
    const linked = await ref.get();
    assert.equal(linked.data()?.linkStatus, undefined);

    assert.equal(await claimManualLinkPropagation('sp1', 'm1', {
      kind: 'initial',
      linkedUid: MARTA,
    }), true);
    const claimed = await ref.get();
    assert.equal(claimed.data()?.linkStatus, 'processing');
    assert.equal(claimed.data()?.linkError, undefined);
    assert.equal(claimed.data()?.linkBlockedSessions, undefined);
  });

  it('dos entregas de la misma versión solo reclaman una propagación',
      async () => {
    await seedSessionWithManual('s1');
    const ref = db().doc('spaces/sp1/manualParticipants/m1');
    await ref.update({ linkedUid: MARTA });
    const results = await Promise.all([
      claimManualLinkPropagation('sp1', 'm1', {
        kind: 'initial',
        linkedUid: MARTA,
      }),
      claimManualLinkPropagation('sp1', 'm1', {
        kind: 'initial',
        linkedUid: MARTA,
      }),
    ]);
    assert.deepEqual(results.sort(), [false, true]);
    assert.equal((await ref.get()).data()?.linkStatus, 'processing');
  });

  it('la escritura processing no vuelve a entrar', async () => {
    await seedSessionWithManual('s1');
    const ref = db().doc('spaces/sp1/manualParticipants/m1');
    await ref.update({ linkedUid: MARTA });
    const initial = await ref.get();
    await claimManualLinkPropagation('sp1', 'm1', {
      kind: 'initial', linkedUid: MARTA,
    });
    const processing = await ref.get();

    await handleManualLinkWrite(
      'sp1', 'm1', initial.data(), processing,
    );
    assert.equal((await ref.get()).data()?.linkStatus, 'processing');
  });

  it('un terminal tardío no sobrescribe otro terminal', async () => {
    await seedSessionWithManual('s1');
    const ref = db().doc('spaces/sp1/manualParticipants/m1');
    await ref.update({ linkedUid: MARTA });
    let after = await ref.get();
    await claimManualLinkPropagation('sp1', 'm1', {
      kind: 'initial',
      linkedUid: MARTA,
    });
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'active', { linkPropagatedSessions: 1 },
    ), true);
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'failed', { linkError: 'propagation-error' },
    ), false);
    assert.equal((await ref.get()).data()?.linkStatus, 'active');

    await ref.update({ linkStatus: 'processing' });
    after = await ref.get();
    assert.equal(after.data()?.linkStatus, 'processing');
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'failed', { linkError: 'propagation-error' },
    ), true);
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'active', { linkPropagatedSessions: 1 },
    ), false);
    assert.equal((await ref.get()).data()?.linkStatus, 'failed');
  });

  it('propaga TODAS las sesiones del espacio, no solo una', async () => {
    await seedSessionWithManual('s1');
    await seedSessionWithManual('s2');
    await recomputeSession('s1');
    await recomputeSession('s2');

    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });
    const result = await propagateManualLink('sp1', 'm1');
    assert.equal(result.sessions, 2);

    for (const entry of await entriesOf()) {
      assert.ok(
        (entry.data.memberUids as string[]).includes(MARTA),
        `la sesión ${entry.data.sessionId ?? entry.id} no se reproyectó`,
      );
    }
  });

  it('propagar es idempotente: repetirlo no cambia nada', async () => {
    await seedSessionWithManual('s1');
    await recomputeSession('s1');
    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });

    await propagateManualLink('sp1', 'm1');
    const primera = await entriesOf();
    await propagateManualLink('sp1', 'm1');
    const segunda = await entriesOf();

    assert.deepEqual(
      segunda.map((e) => ({ id: e.id, m: e.data.memberUids, a: e.data.amount })),
      primera.map((e) => ({ id: e.id, m: e.data.memberUids, a: e.data.amount })),
    );
  });

  // ── M3: sesiones sin contexto estable ─────────────────────────────
  it('M3: una sesión afectada SIN spaceId bloquea el vínculo, no lo omite',
      async () => {
    await seedSessionWithManual('s1');
    // Sesión legacy: tiene al MANUAL pero no tiene contexto. `linkTicket`
    // vincula el TICKET sin tocar la sesión, así que este caso es real.
    await seedSessionWithManual('legacy');
    await db().doc('sessions/legacy').update({ spaceId: FieldValue.delete() });
    await recomputeSession('s1');

    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });
    const result = await propagateManualLink('sp1', 'm1');

    // NO se marca active habiendo dejado economía fuera.
    assert.equal(result.status, 'failed');
    assert.equal(result.reason, 'legacy-sessions-without-context');
    const manual = await db().doc('spaces/sp1/manualParticipants/m1').get();
    assert.equal(manual.data()?.linkStatus, 'failed');
    assert.equal(manual.data()?.linkBlockedSessions, 1);
    // El motivo es un código estable, sin ids ajenos ni rutas.
    assert.equal(manual.data()?.linkError, 'legacy-sessions-without-context');
  });

  it('M3: encuentra las sesiones por el MANUAL, no por session.spaceId',
      async () => {
    // Regresión del criterio: buscar por spaceId omitía sesiones afectadas.
    await seedSessionWithManual('s1');
    await recomputeSession('s1');
    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });
    const result = await propagateManualLink('sp1', 'm1');
    assert.equal(result.sessions, 1, 'la sesión se localiza por participante');
    assert.equal(result.status, 'active');
  });

  // ── Auditoría C1: fallo, reintento y sesiones borradas ────────────
  it('C1: retry seguido de rename tardío llega a `active`', async () => {
    await seedSessionWithManual('s1');
    await seedSessionWithManual('legacy');
    await db().doc('sessions/legacy').update({ spaceId: FieldValue.delete() });
    await recomputeSession('s1');
    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });
    assert.equal((await propagateManualLink('sp1', 'm1')).status, 'failed');

    // Resuelto el bloqueo, el reintento converge.
    await db().doc('sessions/legacy/participants/p2').delete();
    const failed = await db().doc('spaces/sp1/manualParticipants/m1').get();
    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkStatus: 'processing',
    });
    const retry = await db().doc('spaces/sp1/manualParticipants/m1').get();
    await db().doc('spaces/sp1/manualParticipants/m1').update({
      displayName: 'Marta G.',
    });
    await handleManualLinkWrite('sp1', 'm1', failed.data(), retry);
    const manual = await db().doc('spaces/sp1/manualParticipants/m1').get();
    assert.equal(manual.data()?.linkStatus, 'active');
    assert.equal(manual.data()?.linkError, undefined,
      'el motivo del fallo anterior se limpia al recuperarse');
  });

  it('C1: una sesión borrada durante la propagación no la rompe', async () => {
    await seedSessionWithManual('s1');
    await seedSessionWithManual('s2');
    await recomputeSession('s1');
    await recomputeSession('s2');
    // Queda el participante huérfano pero la sesión ya no existe.
    await db().doc('sessions/s2').delete();

    await db().doc('spaces/sp1/manualParticipants/m1').update({
      linkedUid: MARTA,
    });
    const result = await propagateManualLink('sp1', 'm1');
    assert.equal(result.status, 'active');
  });

  it('la proyección de participación por ticket queda consultable',
      async () => {
    await seedSessionWithManual('s1');
    await recomputeSession('s1');
    await waitFor('proyección de participación', async () => {
      const snap = await db()
        .collection('sessions/s1/ticketParticipants')
        .get();
      return snap.size === 2;
    });
    const marker = await db()
      .doc('sessions/s1/ticketParticipantProjections/t1')
      .get();
    assert.equal(marker.data()?.ready, true);
  });
});
