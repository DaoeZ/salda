/**
 * El flujo real de «Nueva relación → alguien sin cuenta», contra las Rules.
 *
 * Replica EXACTAMENTE el batch que ejecuta `createRelationshipWithManual`
 * del repositorio de la app —los tres documentos tal cual, con los mismos
 * campos— en vez de apoyarse en los helpers de `rules.test.mjs`. Así ninguna
 * diferencia de forma puede esconder el problema.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-salda',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

/** Contexto con cuenta completa: verificada, no anónima y con perfil. */
async function cuenta(uid, { provider = 'password', conPerfil = true } = {}) {
  if (conPerfil) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'profiles', uid), {
        displayName: 'Edgar',
        username: uid,
      });
    });
  }
  return env
    .authenticatedContext(uid, {
      email_verified: true,
      firebase: { sign_in_provider: provider },
    })
    .firestore();
}

/** El batch EXACTO del repositorio: espacio v3 + membresía + MANUAL. */
function batchRelacionManual(db, uid, nombre = 'Pablo') {
  const space = doc(collection(db, 'spaces'));
  const manual = doc(collection(space, 'manualParticipants'));
  const batch = writeBatch(db);
  batch.set(space, {
    name: nombre,
    ownerUid: uid,
    kind: 'relationship',
    relationshipUids: [uid],
    relationshipManualId: manual.id,
    status: 'active',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 3,
  });
  batch.set(doc(collection(space, 'members'), uid), {
    uid,
    joinedAt: serverTimestamp(),
  });
  batch.set(manual, {
    manualId: manual.id,
    displayName: nombre,
    linkedUid: null,
    createdByUid: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
  });
  return { batch, space, manual };
}

describe('relación ACCOUNT + MANUAL: el batch real de la app', () => {
  it('una cuenta completa la crea de una sola escritura', async () => {
    const db = await cuenta('uid-edgar');
    const { batch, space, manual } = batchRelacionManual(db, 'uid-edgar');
    await assertSucceeds(batch.commit());

    // Contrato v3 completo, leído de vuelta.
    let escrito;
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      escrito = {
        space: (await getDoc(doc(f, 'spaces', space.id))).data(),
        manual: (
          await getDoc(
            doc(f, 'spaces', space.id, 'manualParticipants', manual.id),
          )
        ).data(),
        member: (
          await getDoc(doc(f, 'spaces', space.id, 'members', 'uid-edgar'))
        ).data(),
      };
    });
    assert.equal(escrito.space.kind, 'relationship');
    assert.equal(escrito.space.schemaVersion, 3);
    assert.equal(escrito.space.relationshipManualId, manual.id);
    assert.deepEqual(escrito.space.relationshipUids, ['uid-edgar']);
    assert.ok(!space.id.startsWith('relationship_'), 'id generado, no canónico');
    assert.equal(escrito.manual.displayName, 'Pablo');
    assert.equal(escrito.manual.linkedUid, null);
    assert.equal(escrito.member.uid, 'uid-edgar');
  });

  it('CON EL TOKEN AÚN ANÓNIMO se deniega entera', async () => {
    // Al convertir un INVITADO en cuenta, `User.isAnonymous` pasa a false en
    // el cliente al instante, pero el ID token conserva
    // `sign_in_provider: 'anonymous'` hasta que se refresca. Rules leen el
    // TOKEN, así que `canUseSocial()` sigue siendo false: la app se cree con
    // cuenta completa y el servidor la trata como invitada. Es el fallo que
    // la UI mostraba como «No se pudo completar la acción».
    const db = await cuenta('uid-converso', { provider: 'anonymous' });
    const { batch } = batchRelacionManual(db, 'uid-converso');
    await assertFails(batch.commit());
  });

  it('SIN PERFIL PÚBLICO se deniega entera', async () => {
    const db = await cuenta('uid-sin-perfil', { conPerfil: false });
    const { batch } = batchRelacionManual(db, 'uid-sin-perfil');
    await assertFails(batch.commit());
  });

  it('no deja datos parciales cuando se deniega', async () => {
    const db = await cuenta('uid-converso', { provider: 'anonymous' });
    const { batch, space, manual } = batchRelacionManual(db, 'uid-converso');
    await assertFails(batch.commit());
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      // Un batch denegado no escribe NADA: ni espacio, ni manual huérfano.
      assert.equal((await getDoc(doc(f, 'spaces', space.id))).exists(), false);
      assert.equal(
        (
          await getDoc(
            doc(f, 'spaces', space.id, 'manualParticipants', manual.id),
          )
        ).exists(),
        false,
      );
    });
  });

  it('otra cuenta no puede fabricar una relación ajena', async () => {
    const db = await cuenta('uid-otro');
    // ownerUid de otra persona: la regla exige que sea quien escribe.
    const space = doc(collection(db, 'spaces'));
    const manual = doc(collection(space, 'manualParticipants'));
    const batch = writeBatch(db);
    batch.set(space, {
      name: 'Pablo',
      ownerUid: 'uid-edgar',
      kind: 'relationship',
      relationshipUids: ['uid-edgar'],
      relationshipManualId: manual.id,
      status: 'active',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 3,
    });
    batch.set(doc(collection(space, 'members'), 'uid-otro'), {
      uid: 'uid-otro',
      joinedAt: serverTimestamp(),
    });
    batch.set(manual, {
      manualId: manual.id,
      displayName: 'Pablo',
      linkedUid: null,
      createdByUid: 'uid-otro',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    await assertFails(batch.commit());
  });

  it('el relationshipManualId no se puede cambiar después', async () => {
    const db = await cuenta('uid-edgar');
    const { batch, space } = batchRelacionManual(db, 'uid-edgar');
    await assertSucceeds(batch.commit());
    await assertFails(
      updateDoc(doc(db, 'spaces', space.id), {
        relationshipManualId: 'otro-manual',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('no se puede añadir un segundo MANUAL a la relación', async () => {
    const db = await cuenta('uid-edgar');
    const { batch, space } = batchRelacionManual(db, 'uid-edgar');
    await assertSucceeds(batch.commit());
    const intruso = doc(collection(db, 'spaces', space.id, 'manualParticipants'));
    await assertFails(
      setDoc(intruso, {
        manualId: intruso.id,
        displayName: 'Ana',
        linkedUid: null,
        createdByUid: 'uid-edgar',
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        schemaVersion: 1,
      }),
    );
  });

  it('una relación v2 entre dos cuentas sigue creándose igual', async () => {
    const db = await cuenta('uid-aaa');
    // La invitada también necesita perfil público: sin él no es alcanzable.
    await cuenta('uid-zzz');
    const spaceId = 'relationship_uid-aaa~uid-zzz';
    const batch = writeBatch(db);
    batch.set(doc(db, 'spaces', spaceId), {
      name: 'Pedro',
      ownerUid: 'uid-aaa',
      kind: 'relationship',
      relationshipUids: ['uid-aaa', 'uid-zzz'],
      status: 'active',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    batch.set(doc(db, 'spaces', spaceId, 'members', 'uid-aaa'), {
      uid: 'uid-aaa',
      joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'spaceInvites', `${spaceId}_uid-zzz`), {
      spaceId,
      spaceName: 'Pedro',
      fromUid: 'uid-aaa',
      toUid: 'uid-zzz',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });
});
