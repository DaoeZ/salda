/**
 * `canUseSocial()`, condición por condición.
 *
 * La cuenta real inicia sesión con Google, tiene el correo verificado y en
 * Ajustes «se ve» configurada, y aun así no puede crear una relación. Estas
 * pruebas aíslan CADA precondición por separado con un token con forma de
 * Google, de modo que un fallo diga exactamente cuál se rompió en vez de
 * agruparlo todo bajo `permission-denied`.
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
  serverTimestamp,
  setDoc,
  writeBatch,
} from 'firebase/firestore';

let env;
const UID = 'uid-google';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-salda',
    firestore: {
      rules: readFileSync(
        new URL('../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

/** Token con la forma del que emite Firebase tras entrar con Google. */
function google({ uid = UID, emailVerified = true, provider = 'google.com' } = {}) {
  return env
    .authenticatedContext(uid, {
      email_verified: emailVerified,
      firebase: { sign_in_provider: provider },
    })
    .firestore();
}

/** Perfil público. `campos` permite simular documentos legacy. */
async function perfilPublico(uid, campos = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'profiles', uid), {
      displayName: 'Edgar',
      username: 'edgar',
      ...campos,
    });
  });
}

/** El batch real de «relación con alguien sin cuenta». */
function crearRelacion(db, uid) {
  const space = doc(collection(db, 'spaces'));
  const manual = doc(collection(space, 'manualParticipants'));
  const batch = writeBatch(db);
  batch.set(space, {
    name: 'Pablo',
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
    displayName: 'Pablo',
    linkedUid: null,
    createdByUid: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
  });
  return batch;
}

describe('canUseSocial: cada precondición por separado', () => {
  it('cuenta de Google verificada CON perfil público: permitido', async () => {
    await perfilPublico(UID);
    await assertSucceeds(crearRelacion(google(), UID).commit());
  });

  it('SIN perfil público: denegado — es la única que falla aquí', async () => {
    // Ni el proveedor ni el correo tienen nada de malo: lo que falta es el
    // documento `profiles/{uid}`, que Ajustes NO mira porque pinta los datos
    // de FirebaseAuth (nombre, correo y verificación vienen de Google).
    await assertFails(crearRelacion(google(), UID).commit());
  });

  it('perfil público LEGACY (sin username) sigue bastando', async () => {
    // `canUseSocial` solo comprueba que el documento EXISTA. Un perfil
    // antiguo e incompleto no es la causa de la denegación.
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Documento de una versión anterior: solo el nombre.
      await setDoc(doc(ctx.firestore(), 'profiles', UID), {
        displayName: 'Edgar',
      });
    });
    await assertSucceeds(crearRelacion(google(), UID).commit());
  });

  it('perfil público vacío también basta para canUseSocial', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'profiles', UID), {});
    });
    await assertSucceeds(crearRelacion(google(), UID).commit());
  });

  it('correo SIN verificar en el token: denegado', async () => {
    await perfilPublico(UID);
    await assertFails(
      crearRelacion(google({ emailVerified: false }), UID).commit(),
    );
  });

  it('token todavía anónimo: denegado', async () => {
    await perfilPublico(UID);
    await assertFails(
      crearRelacion(google({ provider: 'anonymous' }), UID).commit(),
    );
  });

  it('el perfil PRIVADO (users/{uid}) no interviene', async () => {
    // Rules nunca lo lee para esto: tenerlo no arregla nada y no tenerlo
    // tampoco estorba.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', UID), {
        paymentMethods: {},
      });
    });
    await assertFails(crearRelacion(google(), UID).commit());
    await perfilPublico(UID);
    await assertSucceeds(crearRelacion(google(), UID).commit());
  });

  it('una cuenta de Google puede CREAR su perfil público', async () => {
    // La reparación automática del cliente tiene que ser posible: crear el
    // perfil exige `isVerifiedAccount()`, no `canUseSocial()`.
    const db = google();
    const batch = writeBatch(db);
    batch.set(doc(db, 'profiles', UID), {
      displayName: 'Edgar',
      displayNameLower: 'edgar',
      username: 'edgar',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    batch.set(doc(db, 'usernames', 'edgar'), {
      uid: UID,
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    // Y con el perfil ya creado, la relación pasa sin tocar nada más.
    await assertSucceeds(crearRelacion(google(), UID).commit());
  });

  it('la reparación NO puede apropiarse del username de otra persona', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'usernames', 'edgar'), {
        uid: 'uid-otra-persona',
        createdAt: new Date(),
      });
    });
    const db = google();
    const batch = writeBatch(db);
    batch.set(doc(db, 'profiles', UID), {
      displayName: 'Edgar',
      displayNameLower: 'edgar',
      username: 'edgar',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    batch.set(doc(db, 'usernames', 'edgar'), {
      uid: UID,
      createdAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('un grupo tampoco se crea sin perfil público', async () => {
    // La precondición es la misma para TODO el ámbito social; no es algo
    // exclusivo de las relaciones.
    const db = google();
    const space = doc(collection(db, 'spaces'));
    const batch = writeBatch(db);
    batch.set(space, {
      name: 'Piso',
      ownerUid: UID,
      kind: 'group',
      status: 'active',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    batch.set(doc(collection(space, 'members'), UID), {
      uid: UID,
      joinedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
    await perfilPublico(UID);
    assert.ok(true);
  });
});
