/**
 * A11b, capa de archivo: quién puede DESCARGAR la foto del ticket.
 *
 * La evidencia es la foto. Si Firestore abre las líneas al grupo pero
 * Storage sigue cerrado, la auditoría se queda a medias: el miembro ve la
 * interpretación pero no el papel con el que compararla. Estas pruebas
 * comprueban la política del archivo por separado, porque vive en otro
 * servicio y se despliega aparte.
 *
 * Ejecutar desde la raíz del repo (necesita los DOS emuladores: las reglas
 * de Storage consultan Firestore):
 *   firebase emulators:exec --only firestore,storage --project demo-salda \
 *     "npm --prefix backend/firestore test"
 */
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

let env;

const ALBA = 'uid-alba'; // dueña de la sesión: subió la foto
const JORGE = 'uid-jorge'; // miembro normal del grupo
const AJENA = 'uid-ajena'; // miembro de OTRO grupo
const EXTERNO = 'uid-externo'; // sin relación alguna
const PAREJA = 'uid-pareja'; // la otra mitad de una relación

const FOTO = 'receipts/sg1/t1/original.jpg';
const FOTO_OTRO = 'receipts/sg1/t2/original.jpg'; // otro ticket del grupo
const FOTO_REL = 'receipts/sr1/t1/original.jpg';
const FOTO_LEGACY = 'receipts/sl1/t1/original.jpg';

const auth = (uid) =>
  env.authenticatedContext(uid, {
    email: `${uid}@salda.test`,
    email_verified: true,
    firebase: { sign_in_provider: 'password' },
  });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-salda',
    firestore: {
      rules: readFileSync(
        new URL('../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
    storage: {
      rules: readFileSync(
        new URL('../storage.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});
after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'spaces/gr1'), {
      name: 'Piso', ownerUid: ALBA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    for (const uid of [ALBA, JORGE]) {
      await setDoc(doc(f, `spaces/gr1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
      });
    }
    await setDoc(doc(f, 'spaces/gr2'), {
      name: 'Otro', ownerUid: AJENA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    await setDoc(doc(f, `spaces/gr2/members/${AJENA}`), {
      uid: AJENA, joinedAt: serverTimestamp(),
    });
    await setDoc(doc(f, 'spaces/rel1'), {
      name: 'Pareja', ownerUid: ALBA, kind: 'relationship',
      relationshipUids: [ALBA, PAREJA].sort(), status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    for (const uid of [ALBA, PAREJA]) {
      await setDoc(doc(f, `spaces/rel1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
      });
    }

    await setDoc(doc(f, 'sessions/sg1'), {
      ownerUid: ALBA, status: 'open', shareCode: 'SECRET-CODE-16CHARS',
      contextModelVersion: 1, spaceId: 'gr1',
    });
    await setDoc(doc(f, 'sessions/sr1'), {
      ownerUid: ALBA, status: 'open', shareCode: 'SECRET-CODE-16CHARS',
      contextModelVersion: 1, spaceId: 'rel1',
    });
    // Sesión sin contexto: la foto sigue siendo solo suya.
    await setDoc(doc(f, 'sessions/sl1'), {
      ownerUid: ALBA, status: 'open', shareCode: 'SECRET-CODE-16CHARS',
    });

    // A11d: Jorge participó económicamente en t1, no en t2.
    await setDoc(doc(f, `sessions/sg1/ticketEntitlements/t1_${JORGE}`), {
      uid: JORGE, ticketId: 't1', accountId: 'a1',
      participantNames: { p1: 'Alba', p2: 'Jorge' },
      grantedAt: serverTimestamp(), schemaVersion: 1,
    });

    const s = ctx.storage();
    const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    for (const ruta of [FOTO, FOTO_OTRO, FOTO_REL, FOTO_LEGACY]) {
      await uploadBytes(ref(s, ruta), bytes, { contentType: 'image/jpeg' });
    }
  });
});

describe('A11b: la foto del ticket como evidencia del grupo', () => {
  it('quien la subió la sigue leyendo', () =>
    assertSucceeds(getBytes(ref(auth(ALBA).storage(), FOTO))));

  it('un miembro del grupo la abre aunque no sea su ticket', () =>
    assertSucceeds(getBytes(ref(auth(JORGE).storage(), FOTO))));

  it('un miembro de otro grupo no, ni con la ruta exacta', () =>
    assertFails(getBytes(ref(auth(AJENA).storage(), FOTO))));

  it('un externo tampoco', () =>
    assertFails(getBytes(ref(auth(EXTERNO).storage(), FOTO))));

  it('una RELACIÓN mantiene su política: solo el dueño de la sesión', async () => {
    await assertFails(getBytes(ref(auth(PAREJA).storage(), FOTO_REL)));
    await assertSucceeds(getBytes(ref(auth(ALBA).storage(), FOTO_REL)));
  });

  it('una sesión sin contexto no reparte su foto al grupo', () =>
    assertFails(getBytes(ref(auth(JORGE).storage(), FOTO_LEGACY))));

  // Leer no es sustituir: la foto es la prueba y sobrescribirla sería
  // exactamente el fraude que A11b permite detectar.
  it('el miembro que la lee NO puede sustituirla', () =>
    assertFails(uploadBytes(
      ref(auth(JORGE).storage(), FOTO),
      new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
      { contentType: 'image/jpeg' },
    )));

  it('un miembro activo ve también la foto de un ticket suyo y de otro',
    async () => {
      await assertSucceeds(getBytes(ref(auth(JORGE).storage(), FOTO)));
      await assertSucceeds(getBytes(ref(auth(JORGE).storage(), FOTO_OTRO)));
    });
});

// A11d: la foto es parte de la auditoría de una deuda concreta. Expulsar
// corta la auditoría GENERAL del grupo, no la del gasto propio — y esta es
// la mitad de Storage de esa misma frontera.
describe('A11d: la foto tras la expulsión', () => {
  const expulsar = async (uid) => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const { deleteDoc } = await import('firebase/firestore');
      await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${uid}`));
    });
  };

  it('el ex-miembro conserva la foto del ticket en el que participó',
    async () => {
      await expulsar(JORGE);
      await assertSucceeds(getBytes(ref(auth(JORGE).storage(), FOTO)));
    });

  it('pero pierde la de los tickets en los que no participó', async () => {
    await expulsar(JORGE);
    await assertFails(getBytes(ref(auth(JORGE).storage(), FOTO_OTRO)));
  });

  it('sin derecho histórico no conserva ninguna', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const { deleteDoc } = await import('firebase/firestore');
      await deleteDoc(doc(ctx.firestore(),
        `sessions/sg1/ticketEntitlements/t1_${JORGE}`));
    });
    await expulsar(JORGE);
    await assertFails(getBytes(ref(auth(JORGE).storage(), FOTO)));
  });

  it('un externo sigue sin ver nada, tenga quien tenga derecho', async () => {
    await assertFails(getBytes(ref(auth(EXTERNO).storage(), FOTO)));
    await assertFails(getBytes(ref(auth(AJENA).storage(), FOTO)));
  });

  it('el derecho histórico no habilita a SUSTITUIR la foto', async () => {
    await expulsar(JORGE);
    await assertFails(uploadBytes(
      ref(auth(JORGE).storage(), FOTO),
      new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
      { contentType: 'image/jpeg' },
    ));
  });
});
