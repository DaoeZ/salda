/**
 * A2: eliminar un gasto.
 *
 * Dos fronteras y una evidencia. Quién puede borrar (su creador —que en este
 * modelo es el dueño de la sesión— y quien administra el GRUPO; una relación
 * no adquiere esa figura) y cuándo (nunca con la sesión cerrada). Y sobre
 * todo: el borrado y la evidencia de QUIÉN lo hizo viajan en el MISMO commit,
 * porque el trigger de borrado solo recibe el cambio neto y sin evidencia P6
 * atribuiría el hecho al dueño de la sesión — falsamente y para siempre.
 *
 * Ejecutar desde la raíz del repo:
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
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

const JEFA = 'uid-jefa'; // propietaria del grupo
const ADMIN = 'uid-admin'; // role: admin en el grupo
const ALBA = 'uid-alba'; // subió el ticket = dueña de la sesión
const JORGE = 'uid-jorge'; // miembro normal del grupo
const AJENA = 'uid-ajena'; // administra OTRO grupo
const PAREJA = 'uid-pareja'; // la otra mitad de la relación

const SG = 'sessions/sg1'; // sesión del GRUPO
const SR = 'sessions/sr1'; // sesión de la RELACIÓN

const db = (uid) =>
  env
    .authenticatedContext(uid, {
      email: `${uid}@salda.test`,
      email_verified: true,
      firebase: { sign_in_provider: 'password' },
    })
    .firestore();

/** El borrado REAL: evidencia + delete en un solo commit. */
const eliminar = (actor, { sid = 'sg1', tid = 't1', aid = 'a1', ...campos } = {}) => {
  const f = db(actor);
  const batch = writeBatch(f);
  batch.set(doc(f, `sessions/${sid}/ticketRemovals/${tid}`), {
    ticketId: tid,
    accountId: aid,
    merchantName: 'Familycash',
    grandTotal: 1596,
    removedBy: actor,
    removedAt: serverTimestamp(),
    schemaVersion: 1,
    ...campos,
  });
  batch.delete(doc(f, `sessions/${sid}/accounts/${aid}/tickets/${tid}`));
  return batch.commit();
};

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

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of [JEFA, ADMIN, ALBA, JORGE, AJENA, PAREJA]) {
      await setDoc(doc(f, `profiles/${uid}`), {
        displayName: uid, displayNameLower: uid, username: uid,
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
    }

    await setDoc(doc(f, 'spaces/gr1'), {
      name: 'Piso', ownerUid: JEFA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    for (const uid of [JEFA, ADMIN, ALBA, JORGE]) {
      await setDoc(doc(f, `spaces/gr1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
        ...(uid === ADMIN ? { role: 'admin' } : {}),
      });
    }
    // Otro grupo: su administradora no manda aquí.
    await setDoc(doc(f, 'spaces/gr2'), {
      name: 'Otro', ownerUid: AJENA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    await setDoc(doc(f, `spaces/gr2/members/${AJENA}`), {
      uid: AJENA, joinedAt: serverTimestamp(),
    });
    // Relación: sin administradores, ni siquiera para su propietaria.
    await setDoc(doc(f, 'spaces/rel1'), {
      name: 'Pareja', ownerUid: JEFA, kind: 'relationship',
      relationshipUids: [ALBA, PAREJA].sort(), status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    for (const uid of [ALBA, PAREJA]) {
      await setDoc(doc(f, `spaces/rel1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
      });
    }

    for (const [sid, spaceId] of [['sg1', 'gr1'], ['sr1', 'rel1']]) {
      await setDoc(doc(f, `sessions/${sid}`), {
        ownerUid: ALBA, kind: 'multi', name: 'Compra', status: 'open',
        splitModeDefault: 'byItem', shareCode: 'SECRET-CODE-16CHARS',
        currency: 'EUR', contextModelVersion: 1, spaceId,
        computeVersion: 0, totals: { grandTotal: 1596 }, balances: {},
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1`), {
        name: 'Súper', order: 0,
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1`), {
        kind: 'scanned', grandTotal: 1596, paidByParticipantId: 'p1',
        merchant: { name: 'Familycash' }, spaceId, contextModelVersion: 1,
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1/lines/l1`), {
        name: 'Patatas', totalPrice: 1596, quantityMilli: 1000, order: 0,
      });
    }
  });
});

describe('A2: autoridad para eliminar un gasto', () => {
  it('el creador del ticket (dueño de la sesión) borra el suyo en un grupo',
    () => assertSucceeds(eliminar(ALBA)));

  it('el creador del ticket borra el suyo en una relación', () =>
    assertSucceeds(eliminar(ALBA, { sid: 'sr1' })));

  it('quien administra el grupo borra el ticket ajeno', () =>
    assertSucceeds(eliminar(ADMIN, { removedBy: ADMIN })));

  it('el propietario del grupo borra el ticket ajeno', () =>
    assertSucceeds(eliminar(JEFA, { removedBy: JEFA })));

  it('un miembro normal NO borra el ticket de otro', () =>
    assertFails(eliminar(JORGE, { removedBy: JORGE })));

  it('la contraparte de una RELACIÓN no borra el ticket de la otra', () =>
    assertFails(eliminar(PAREJA, { sid: 'sr1', removedBy: PAREJA })));

  it('la propietaria de la RELACIÓN tampoco: no hay administración', () =>
    assertFails(eliminar(JEFA, { sid: 'sr1', removedBy: JEFA })));

  it('quien administra OTRO grupo no borra aquí', () =>
    assertFails(eliminar(AJENA, { removedBy: AJENA })));

  it('con la sesión CERRADA nadie borra, ni su dueña', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), SG), { status: 'closed' }));
    await assertFails(eliminar(ALBA));
    await assertFails(eliminar(ADMIN, { removedBy: ADMIN }));
  });
});

describe('A2: atomicidad y honestidad de la evidencia', () => {
  it('borrar SIN dejar evidencia: denegado', () =>
    assertFails(deleteDoc(doc(db(ALBA), `${SG}/accounts/a1/tickets/t1`))));

  it('dejar evidencia SIN borrar: denegado', () =>
    assertFails(setDoc(doc(db(ALBA), `${SG}/ticketRemovals/t1`), {
      ticketId: 't1', accountId: 'a1', merchantName: 'Familycash',
      grandTotal: 1596, removedBy: ALBA, removedAt: serverTimestamp(),
      schemaVersion: 1,
    })));

  it('el actor no se puede falsear', () =>
    assertFails(eliminar(ADMIN, { removedBy: ALBA })));

  it('la hora no se puede falsear', () =>
    assertFails(eliminar(ALBA, { removedAt: Timestamp.fromMillis(1) })));

  it('el importe tiene que ser el del ticket', () =>
    assertFails(eliminar(ALBA, { grandTotal: 100 })));

  it('el comercio tiene que ser el del ticket', () =>
    assertFails(eliminar(ALBA, { merchantName: 'Inventado' })));

  it('la evidencia no puede señalar otra cuenta', () =>
    assertFails(eliminar(ALBA, { accountId: 'a9' })));

  it('no hay evidencia de un ticket que no existe', () =>
    assertFails(setDoc(doc(db(ALBA), `${SG}/ticketRemovals/t9`), {
      ticketId: 't9', accountId: 'a1', merchantName: 'Fantasma',
      grandTotal: 0, removedBy: ALBA, removedAt: serverTimestamp(),
      schemaVersion: 1,
    })));

  it('la evidencia es INMUTABLE: ni update ni delete', async () => {
    await assertSucceeds(eliminar(ALBA));
    const ruta = `${SG}/ticketRemovals/t1`;
    await assertFails(updateDoc(doc(db(ALBA), ruta), { removedBy: JORGE }));
    await assertFails(deleteDoc(doc(db(ALBA), ruta)));
    await assertFails(deleteDoc(doc(db(JEFA), ruta)));
  });

  it('la lee quien podía ver el gasto, y nadie más', async () => {
    await assertSucceeds(eliminar(ALBA));
    const ruta = `${SG}/ticketRemovals/t1`;
    await assertSucceeds(getDoc(doc(db(ALBA), ruta))); // dueña de la sesión
    await assertSucceeds(getDoc(doc(db(JORGE), ruta))); // miembro del grupo
    await assertFails(getDoc(doc(db(AJENA), ruta))); // ajena al grupo
  });

  it('la evidencia NO abre el ticket: es auditoría, no papelera', async () => {
    // Se siembra un ticket que sobrevive y una evidencia de otro: leer la
    // evidencia nunca puede convertirse en leer contenido.
    await assertSucceeds(eliminar(ALBA));
    await assertFails(
      getDoc(doc(db(AJENA), `${SG}/accounts/a1/tickets/t1`)));
  });
});
