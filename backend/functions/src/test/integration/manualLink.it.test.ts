/**
 * Prueba INTEGRADA del flujo real de vinculación (C1) contra el emulador.
 *
 * No inyecta `manualAliases` a mano: escribe los documentos que escribe la
 * app, ejecuta el mecanismo real y comprueba el efecto observable. Es la
 * prueba que faltaba y por la que C1 pasó desapercibido.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import {
  claimManualLinkPropagation,
  handleManualLinkWrite,
  propagateManualLink,
  publishManualLinkTerminal,
  requestManualLink,
  retryManualLinkPropagation,
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

const callRetry = (data: unknown, uid?: string) =>
  retryManualLinkPropagation.run({
    data,
    auth: uid
      ? { uid, token: { uid } as never, rawToken: 'test-token' }
      : undefined,
    rawRequest: {} as never,
    acceptsStreaming: false,
  });

const callRequest = (
  data: unknown,
  uid?: string,
  token: Record<string, unknown> = {},
) => requestManualLink.run({
  data,
  auth: uid
    ? {
      uid,
      token: {
        uid,
        email_verified: true,
        firebase: { sign_in_provider: 'password' },
        ...token,
      } as never,
      rawToken: 'test-token',
    }
    : undefined,
  rawRequest: {} as never,
  acceptsStreaming: false,
});

async function expectCallableCode(
  call: Promise<unknown>,
  code: string,
): Promise<void> {
  await assert.rejects(call, (error: unknown) => {
    assert.equal((error as { code?: string }).code, code);
    return true;
  });
}

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

  async function seedRequestContext({
    uid = MARTA,
    owner = OWNER,
    member = false,
    ticketRecipient = false,
    profile = true,
  }: {
    uid?: string;
    owner?: string;
    member?: boolean;
    ticketRecipient?: boolean;
    profile?: boolean;
  } = {}): Promise<void> {
    const f = db();
    await f.doc('spaces/sp1').set({
      name: 'Piso', ownerUid: owner, status: 'active',
      kind: 'group', schemaVersion: 2,
    });
    await f.doc('spaces/sp1/manualParticipants/m1').set({
      manualId: 'm1', displayName: 'Marta', linkedUid: null,
      createdByUid: owner, schemaVersion: 1,
    });
    if (profile) await f.doc(`profiles/${uid}`).set({ displayName: 'Marta' });
    if (member) {
      await f.doc(`spaces/sp1/members/${uid}`).set({ uid, role: 'member' });
    }
    if (!ticketRecipient) return;
    await f.doc('ticketLinks/TOKEN').set({
      sessionId: 's1', accountId: 'a1', ticketId: 't1',
      targetPid: 'p2', targetManualId: 'm1', status: 'active',
      createdByUid: 'session-creator',
      schemaVersion: 2,
    });
    await f.doc(`sessions/s1/ticketAccess/t1_${uid}`).set({
      uid, token: 'TOKEN', ticketId: 't1', pid: 'p2', manualId: 'm1',
    });
    await f.doc('sessions/s1/ticketParticipants/t1_p2').set({
      ticketId: 't1', pid: 'p2', schemaVersion: 1,
    });
  }

  async function seedRetryManual(
    fields: Record<string, unknown> = {},
  ): Promise<void> {
    const f = db();
    await f.doc('spaces/sp1').set({
      name: 'Piso', ownerUid: OWNER, status: 'active',
      kind: 'group', schemaVersion: 2,
    });
    await f.doc('spaces/sp1/manualParticipants/m1').set({
      manualId: 'm1', displayName: 'Marta', linkedUid: MARTA,
      createdByUid: OWNER, schemaVersion: 1, updatedAt: Timestamp.now(),
      ...fields,
    });
  }

  const entriesOf = async (): Promise<
    Array<{ id: string; data: FirebaseFirestore.DocumentData }>
  > => {
    const snap = await db().collection('economicEntries').get();
    return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  };

  it('requestManualLink bloquea cuenta anónima, sin verificar, sin perfil y ajena',
      async () => {
    await seedRequestContext();
    const input = { spaceId: 'sp1', manualId: 'm1', displayName: 'Marta' };
    await expectCallableCode(callRequest(input), 'unauthenticated');
    await expectCallableCode(callRequest(input, MARTA, {
      firebase: { sign_in_provider: 'anonymous' },
    }), 'permission-denied');
    await expectCallableCode(callRequest(input, MARTA, {
      email_verified: false,
    }), 'permission-denied');
    await clearFirestore();
    await seedRequestContext({ profile: false });
    await expectCallableCode(callRequest(input, MARTA), 'permission-denied');
    await clearFirestore();
    await seedRequestContext();
    await expectCallableCode(callRequest(input, MARTA), 'permission-denied');
  });

  it('requestManualLink acepta miembro y deriva el owner vigente tras transferir',
      async () => {
    await seedRequestContext({ member: true });
    await db().doc('spaces/sp1').update({ ownerUid: 'nuevo-owner' });
    const result = await callRequest({
      spaceId: 'sp1', manualId: 'm1', displayName: ' Marta ',
    }, MARTA);
    assert.equal(result.action, 'created');
    const request = await db()
      .doc(`spaces/sp1/manualLinkRequests/m1_${MARTA}`)
      .get();
    assert.equal(request.data()?.spaceOwnerUid, 'nuevo-owner');
    assert.equal(request.data()?.uid, MARTA);
    assert.equal(request.data()?.displayName, 'Marta');
  });

  it('requestManualLink acepta al destinatario, rechaza datos inyectados y no sobrescribe',
      async () => {
    await seedRequestContext({ ticketRecipient: true });
    const input = {
      spaceId: 'sp1', manualId: 'm1', displayName: 'Marta',
      viaSessionId: 's1', viaTicketId: 't1', viaPid: 'p2',
    };
    assert.equal((await callRequest(input, MARTA)).action, 'created');
    assert.equal((await callRequest(input, MARTA)).action, 'pending');
    await expectCallableCode(callRequest({ ...input, uid: OWNER }, MARTA),
      'invalid-argument');
    await expectCallableCode(callRequest({ ...input, spaceOwnerUid: OWNER }, MARTA),
      'invalid-argument');
    const ref = db().doc(`spaces/sp1/manualLinkRequests/m1_${MARTA}`);
    await ref.update({ status: 'rejected', attempt: 7 });
    assert.equal((await callRequest(input, MARTA)).action, 'rejected');
    assert.equal((await ref.get()).data()?.attempt, 7);
    await ref.update({ status: 'accepted', actor: 'preserve' });
    assert.equal((await callRequest(input, MARTA)).action, 'accepted');
    assert.equal((await ref.get()).data()?.actor, 'preserve');
  });

  it('requestManualLink rechaza enlaces expirados o con expiry malformado',
      async () => {
    const input = {
      spaceId: 'sp1', manualId: 'm1', displayName: 'Marta',
      viaSessionId: 's1', viaTicketId: 't1', viaPid: 'p2',
    };
    await seedRequestContext({ ticketRecipient: true });
    await db().doc('ticketLinks/TOKEN').update({
      expiresAt: Timestamp.fromMillis(Date.now() - 1),
    });
    await expectCallableCode(callRequest(input, MARTA), 'permission-denied');
    await clearFirestore();
    await seedRequestContext({ ticketRecipient: true });
    await db().doc('ticketLinks/TOKEN').update({ expiresAt: 'not-a-timestamp' });
    await expectCallableCode(callRequest(input, MARTA), 'permission-denied');
  });

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
    assert.equal(typeof claimed.data()?.linkClaimId, 'string');
    assert.ok(claimed.data()?.linkProcessingAt);
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
    const claimId = processing.data()?.linkClaimId;

    await handleManualLinkWrite(
      'sp1', 'm1', initial.data(), processing,
    );
    assert.equal((await ref.get()).data()?.linkStatus, 'processing');
    assert.equal((await ref.get()).data()?.linkClaimId, claimId);
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
    const firstClaimId = (await ref.get()).data()?.linkClaimId as string;
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, firstClaimId, 'active',
      { linkPropagatedSessions: 1 },
    ), true);
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, firstClaimId, 'failed',
      { linkError: 'propagation-error' },
    ), false);
    assert.equal((await ref.get()).data()?.linkStatus, 'active');

    await ref.update({
      linkStatus: 'processing',
      linkClaimId: 'claim-2',
      linkProcessingAt: FieldValue.serverTimestamp(),
    });
    after = await ref.get();
    assert.equal(after.data()?.linkStatus, 'processing');
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'claim-2', 'failed',
      { linkError: 'propagation-error' },
    ), true);
    assert.equal(await publishManualLinkTerminal(
      'sp1', 'm1', MARTA, 'claim-2', 'active',
      { linkPropagatedSessions: 1 },
    ), false);
    assert.equal((await ref.get()).data()?.linkStatus, 'failed');
  });

  it('un fallo de adquisicion antes del claim no muta el manual', async () => {
    await seedRetryManual();
    const f = db();
    const manualPath = 'spaces/sp1/manualParticipants/m1';
    const before = (await f.doc(manualPath).get()).data()!;
    type RunTransaction = (
      updateFunction: (transaction: FirebaseFirestore.Transaction) => Promise<unknown>,
      ...rest: unknown[]
    ) => Promise<unknown>;
    const originalRunTransaction = f.runTransaction.bind(f) as unknown as RunTransaction;
    const patchedFirestore = f as unknown as { runTransaction: RunTransaction };
    patchedFirestore.runTransaction = async () => {
      throw new Error('forced-acquisition-outage');
    };

    try {
      await assert.rejects(
        propagateManualLink('sp1', 'm1'),
        /forced-acquisition-outage/,
      );
    } finally {
      patchedFirestore.runTransaction = originalRunTransaction;
    }

    const after = (await f.doc(manualPath).get()).data()!;
    assert.deepEqual(after, before);
    assert.equal(after.linkedUid, MARTA);
    assert.equal(after.linkStatus, undefined);
    assert.equal(after.linkClaimId, undefined);
  });

  it('un fallo de consulta afectada tras el claim publica failed por CAS', async () => {
    await seedRetryManual();
    const f = db();
    const manualPath = 'spaces/sp1/manualParticipants/m1';
    type CollectionGroup = (collectionId: string) => unknown;
    const originalCollectionGroup = f.collectionGroup.bind(f) as unknown as CollectionGroup;
    const patchedFirestore = f as unknown as { collectionGroup: CollectionGroup };
    patchedFirestore.collectionGroup = (collectionId) =>
      collectionId === 'participants'
        ? {
          where: () => ({
            get: async () => { throw new Error('forced-affected-query-outage'); },
          }),
        }
        : originalCollectionGroup(collectionId);

    try {
      const result = await propagateManualLink('sp1', 'm1');
      assert.deepEqual(result, {
        sessions: 0, status: 'failed', reason: 'propagation-error',
      });
    } finally {
      patchedFirestore.collectionGroup = originalCollectionGroup;
    }

    const manual = (await f.doc(manualPath).get()).data()!;
    assert.equal(manual.linkedUid, MARTA);
    assert.equal(manual.linkStatus, 'failed');
    assert.equal(manual.linkError, 'propagation-error');
    assert.equal(manual.linkClaimId, undefined);
    assert.equal(manual.linkProcessingAt, undefined);
  });

  it('un fallo de recompute tras el claim publica failed y conserva economia',
      async () => {
    await seedSessionWithManual('s1');
    await recomputeSession('s1');
    const f = db();
    const manualPath = 'spaces/sp1/manualParticipants/m1';
    const beforeEntries = (await entriesOf()).map((entry) => ({
      id: entry.id,
      amount: entry.data.amount,
      debtorUid: entry.data.debtorUid,
      creditorUid: entry.data.creditorUid,
    }));
    await f.doc(manualPath).update({ linkedUid: MARTA });

    type Document = (path: string) => FirebaseFirestore.DocumentReference;
    const originalDoc = f.doc.bind(f) as unknown as Document;
    const patchedFirestore = f as unknown as { doc: Document };
    let sessionReads = 0;
    patchedFirestore.doc = (path) => {
      const ref = originalDoc(path);
      if (path !== 'sessions/s1') return ref;
      return new Proxy(ref, {
        get(target, property, receiver) {
          if (property === 'get') {
            return () => {
              if (++sessionReads === 2) {
                throw new Error('forced-recompute-outage');
              }
              return target.get();
            };
          }
          const value = Reflect.get(target, property, receiver);
          return typeof value === 'function' ? value.bind(target) : value;
        },
      }) as FirebaseFirestore.DocumentReference;
    };

    try {
      const result = await propagateManualLink('sp1', 'm1');
      assert.deepEqual(result, {
        sessions: 1, status: 'failed', reason: 'propagation-error',
      });
    } finally {
      patchedFirestore.doc = originalDoc;
    }

    const manual = (await f.doc(manualPath).get()).data()!;
    assert.equal(manual.linkedUid, MARTA);
    assert.equal(manual.linkStatus, 'failed');
    assert.equal(manual.linkError, 'propagation-error');
    assert.equal(manual.linkClaimId, undefined);
    assert.equal(manual.linkProcessingAt, undefined);
    assert.deepEqual((await entriesOf()).map((entry) => ({
      id: entry.id,
      amount: entry.data.amount,
      debtorUid: entry.data.debtorUid,
      creditorUid: entry.data.creditorUid,
    })), beforeEntries);
  });

  it('un fallo al publicar active conserva processing recuperable', async () => {
    await seedRetryManual();
    const f = db();
    const manualPath = 'spaces/sp1/manualParticipants/m1';
    type RunTransaction = (
      updateFunction: (transaction: FirebaseFirestore.Transaction) => Promise<unknown>,
      ...rest: unknown[]
    ) => Promise<unknown>;
    const originalRunTransaction = f.runTransaction.bind(f) as unknown as RunTransaction;
    const patchedFirestore = f as unknown as { runTransaction: RunTransaction };
    let manualTransactionReads = 0;

    patchedFirestore.runTransaction = (updateFunction, ...rest) =>
      originalRunTransaction(async (transaction) => {
        const guardedTransaction = new Proxy(transaction, {
          get(target, property, receiver) {
            if (property === 'get') {
              return (ref: FirebaseFirestore.DocumentReference) => {
                if (ref.path === manualPath && ++manualTransactionReads === 2) {
                  throw new Error('forced-terminal-write-outage');
                }
                return target.get(ref);
              };
            }
            const value = Reflect.get(target, property, receiver);
            return typeof value === 'function' ? value.bind(target) : value;
          },
        }) as FirebaseFirestore.Transaction;
        return updateFunction(guardedTransaction);
      }, ...rest);

    try {
      await assert.rejects(
        propagateManualLink('sp1', 'm1'),
        /forced-terminal-write-outage/,
      );
    } finally {
      patchedFirestore.runTransaction = originalRunTransaction;
    }

    const manual = (await f.doc(manualPath).get()).data()!;
    assert.equal(manual.linkStatus, 'processing');
    assert.equal(typeof manual.linkClaimId, 'string');
    assert.ok(manual.linkProcessingAt);
    assert.equal(manual.linkError, undefined);
  });

  describe('reintento callable', () => {
    it('autoriza al propietario y al linkedUid exacto, y deja traza',
        async () => {
      await seedRetryManual({
        linkStatus: 'failed',
        linkError: 'propagation-error',
        linkRetryCount: 2,
      });
      const ownerResult = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { status: string; action: string };
      assert.deepEqual(ownerResult, {
        status: 'active', action: 'claimed', sessions: 0,
      });
      let data = (await db().doc('spaces/sp1/manualParticipants/m1').get())
        .data()!;
      assert.equal(data.linkedUid, MARTA);
      assert.equal(data.linkRetryCount, 3);
      assert.equal(data.linkRetryRequestedBy, OWNER);
      assert.ok(data.linkRetryRequestedAt);
      assert.equal(data.linkClaimId, undefined);
      assert.equal(data.linkProcessingAt, undefined);

      await seedRetryManual({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      const linkedResult = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, MARTA,
      ) as { status: string; action: string };
      assert.equal(linkedResult.status, 'active');
      data = (await db().doc('spaces/sp1/manualParticipants/m1').get())
        .data()!;
      assert.equal(data.linkRetryRequestedBy, MARTA);
      assert.equal(data.linkedUid, MARTA);
    });

    it('rechaza llamadas no autenticadas, ajenas, con UID forjado o datos extra',
        async () => {
      await seedRetryManual({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      await expectCallableCode(
        callRetry({ spaceId: 'sp1', manualId: 'm1' }),
        'unauthenticated',
      );
      await expectCallableCode(
        callRetry({ spaceId: 'sp1', manualId: 'm1' }, 'uid-tercero'),
        'permission-denied',
      );
      await expectCallableCode(
        callRetry({
          spaceId: 'sp1', manualId: 'm1', linkedUid: OWNER,
        }, OWNER),
        'invalid-argument',
      );
      await expectCallableCode(
        callRetry({ spaceId: 'sp/1', manualId: 'm1' }, OWNER),
        'invalid-argument',
      );
    });

    it('rechaza espacio/manual inexistente y manual sin vínculo', async () => {
      await seedRetryManual();
      await expectCallableCode(
        callRetry({ spaceId: 'sp1', manualId: 'missing' }, OWNER),
        'not-found',
      );
      await expectCallableCode(
        callRetry({ spaceId: 'missing', manualId: 'm1' }, OWNER),
        'not-found',
      );
      await db().doc('spaces/sp1/manualParticipants/m1').update({
        linkedUid: null,
      });
      await expectCallableCode(
        callRetry({ spaceId: 'sp1', manualId: 'm1' }, OWNER),
        'failed-precondition',
      );
    });

    it('active es no-op y processing fresco responde en curso', async () => {
      const requestedAt = Timestamp.now();
      await seedRetryManual({
        linkStatus: 'active', linkPropagatedSessions: 2,
        linkRetryCount: 4, linkRetryRequestedAt: requestedAt,
        linkRetryRequestedBy: OWNER,
      });
      const activeBefore = (await db().doc(
        'spaces/sp1/manualParticipants/m1',
      ).get()).data()!;
      const activeResult = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { status: string; action: string };
      assert.deepEqual(activeResult, { status: 'active', action: 'active' });
      assert.deepEqual(
        (await db().doc('spaces/sp1/manualParticipants/m1').get()).data(),
        activeBefore,
      );

      await seedRetryManual({
        linkStatus: 'processing', linkClaimId: 'fresh-claim',
        linkProcessingAt: Timestamp.now(), linkRetryCount: 1,
      });
      const processingResult = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, MARTA,
      ) as { status: string; action: string };
      assert.deepEqual(processingResult, {
        status: 'processing', action: 'in-progress',
      });
      const processing = (await db().doc(
        'spaces/sp1/manualParticipants/m1',
      ).get()).data()!;
      assert.equal(processing.linkClaimId, 'fresh-claim');
      assert.equal(processing.linkRetryCount, 1);
    });

    it('reclama lease servidor caducado y conserva el linkedUid', async () => {
      await seedRetryManual({
        linkStatus: 'processing', linkClaimId: 'expired-claim',
        linkProcessingAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
      });
      const result = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, MARTA,
      ) as { status: string; action: string };
      assert.deepEqual(result, {
        status: 'active', action: 'claimed', sessions: 0,
      });
      const data = (await db().doc('spaces/sp1/manualParticipants/m1').get())
        .data()!;
      assert.equal(data.linkedUid, MARTA);
      assert.equal(data.linkRetryCount, 1);
      assert.equal(data.linkRetryRequestedBy, MARTA);
    });

    it('processing sin lease no se recupera ni muta el documento', async () => {
      await seedRetryManual({
        linkStatus: 'processing', linkError: 'legacy-marker',
      });
      const before = (await db().doc(
        'spaces/sp1/manualParticipants/m1',
      ).get()).data()!;
      const result = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { status: string; action: string };
      assert.deepEqual(result, {
        status: 'processing', action: 'unclassifiable',
      });
      assert.deepEqual(
        (await db().doc('spaces/sp1/manualParticipants/m1').get()).data(),
        before,
      );
    });

    it('aplica cooldown después de un fallo real y no reclama otra vez',
        async () => {
      await seedRetryManual({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      await db().doc('sessions/s1/participants/p1').set({
        manualId: 'm1', active: true,
      });
      await db().doc('sessions/s1').set({
        ownerUid: OWNER, kind: 'single', status: 'open',
        // Sin spaceId: fuerza el fallo legacy sin tocar economía.
      });
      const first = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { status: string; action: string };
      assert.deepEqual(first, {
        status: 'failed', action: 'claimed', sessions: 1,
        reason: 'legacy-sessions-without-context',
      });
      const second = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { status: string; action: string };
      assert.deepEqual(second, { status: 'failed', action: 'cooldown' });
      assert.equal(
        (await db().doc('spaces/sp1/manualParticipants/m1').get())
          .data()?.linkRetryCount,
        1,
      );
    });

    it('sin status adquiere el claim inicial y hace una sola propagación',
        async () => {
      await seedRetryManual();
      const result = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, MARTA,
      ) as { status: string; action: string };
      assert.deepEqual(result, {
        status: 'active', action: 'claimed', sessions: 0,
      });
      const data = (await db().doc('spaces/sp1/manualParticipants/m1').get())
        .data()!;
      assert.equal(data.linkedUid, MARTA);
      assert.equal(data.linkRetryRequestedBy, MARTA);
      assert.equal(data.linkRetryCount, undefined);
      assert.equal(data.linkClaimId, undefined);
    });

    it('llamadas repetidas y concurrentes convergen en un claim', async () => {
      await seedRetryManual({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      const repeated = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { action: string };
      const again = await callRetry(
        { spaceId: 'sp1', manualId: 'm1' }, OWNER,
      ) as { action: string };
      assert.equal(repeated.action, 'claimed');
      assert.equal(again.action, 'active');
      assert.equal(
        (await db().doc('spaces/sp1/manualParticipants/m1').get())
          .data()?.linkRetryCount,
        1,
      );

      await seedRetryManual({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      const concurrent = await Promise.all([
        callRetry({ spaceId: 'sp1', manualId: 'm1' }, OWNER),
        callRetry({ spaceId: 'sp1', manualId: 'm1' }, MARTA),
      ]) as Array<{ action: string }>;
      const actions = concurrent.map((entry) => entry.action);
      assert.equal(actions.filter((action) => action === 'claimed').length, 1);
      assert.ok(actions.some((action) =>
        action === 'active' || action === 'in-progress'));
      assert.equal(
        (await db().doc('spaces/sp1/manualParticipants/m1').get())
          .data()?.linkRetryCount,
        1,
      );
    });

    it('mantiene actores/importes y el segundo intento es idempotente',
        async () => {
      await seedSessionWithManual('s1');
      await recomputeSession('s1');
      const before = (await entriesOf()).map((entry) => ({
        id: entry.id,
        amount: entry.data.amount,
        debtorUid: entry.data.debtorUid,
        creditorUid: entry.data.creditorUid,
      }));
      await db().doc('spaces/sp1/manualParticipants/m1').update({
        linkedUid: MARTA,
        linkStatus: 'failed',
        linkError: 'propagation-error',
      });
      await callRetry({ spaceId: 'sp1', manualId: 'm1' }, OWNER);
      const after = (await entriesOf()).map((entry) => ({
        id: entry.id,
        amount: entry.data.amount,
        debtorUid: entry.data.debtorUid,
        creditorUid: entry.data.creditorUid,
      }));
      assert.deepEqual(after, before);
      assert.equal(
        (await db().doc('spaces/sp1/manualParticipants/m1').get())
          .data()?.linkedUid,
        MARTA,
      );
      await callRetry({ spaceId: 'sp1', manualId: 'm1' }, OWNER);
      assert.deepEqual(
        (await entriesOf()).map((entry) => ({
          id: entry.id,
          amount: entry.data.amount,
          debtorUid: entry.data.debtorUid,
          creditorUid: entry.data.creditorUid,
        })),
        after,
      );
    });

    it('un terminal antiguo no puede publicar tras un claim nuevo', async () => {
      await seedRetryManual();
      const ref = db().doc('spaces/sp1/manualParticipants/m1');
      assert.equal(await claimManualLinkPropagation('sp1', 'm1', {
        kind: 'initial', linkedUid: MARTA,
      }), true);
      const oldClaim = (await ref.get()).data()?.linkClaimId as string;
      await ref.update({
        linkStatus: 'failed', linkError: 'propagation-error',
      });
      await ref.update({ linkStatus: 'processing' });
      assert.equal(await claimManualLinkPropagation('sp1', 'm1', {
        kind: 'retry', linkedUid: MARTA, linkError: 'propagation-error',
      }), true);
      const newClaim = (await ref.get()).data()?.linkClaimId as string;
      assert.notEqual(newClaim, oldClaim);
      assert.equal(await publishManualLinkTerminal(
        'sp1', 'm1', MARTA, oldClaim, 'active',
        { linkPropagatedSessions: 99 },
      ), false);
      assert.equal(await publishManualLinkTerminal(
        'sp1', 'm1', MARTA, newClaim, 'active',
        { linkPropagatedSessions: 0 },
      ), true);
      assert.equal((await ref.get()).data()?.linkStatus, 'active');
      assert.equal((await ref.get()).data()?.linkPropagatedSessions, 0);
    });
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
