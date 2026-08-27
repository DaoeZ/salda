/**
 * A11d — derecho histórico por ticket (proyección C).
 *
 * Expulsar corta el acceso al grupo, pero no puede arrancarle a nadie el
 * gasto que explica SU deuda. La frontera es estrecha a propósito:
 * historial económico PROPIO ≠ membresía histórica del grupo.
 *
 * `sessions/{sid}/ticketEntitlements/{tid}_{uid}` lo escribe SOLO recompute
 * y no se retira nunca; aquí se siembra con Admin porque estas pruebas miden
 * las Rules, no la proyección (eso lo cubre `recompute.test.ts`).
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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

const JEFA = 'uid-jefa'; // propietaria del grupo
const ALBA = 'uid-alba'; // dueña de la sesión, pagadora del ticket
const JORGE = 'uid-jorge'; // consumió del ticket t1; luego lo expulsan
const ADMIN = 'uid-admin'; // administrador expulsado más tarde
const EXTERNO = 'uid-externo'; // cuenta sin relación alguna

const SG = 'sessions/sg1';
const T1 = `${SG}/accounts/a1/tickets/t1`; // Jorge participa
const T2 = `${SG}/accounts/a1/tickets/t2`; // Jorge NO participa

const db = (uid) =>
  env
    .authenticatedContext(uid, {
      email: `${uid}@salda.test`,
      email_verified: true,
      firebase: { sign_in_provider: 'password' },
    })
    .firestore();

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
    for (const uid of [JEFA, ALBA, JORGE, ADMIN, EXTERNO]) {
      await setDoc(doc(f, `profiles/${uid}`), {
        displayName: uid, displayNameLower: uid, username: uid,
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
    }
    await setDoc(doc(f, 'spaces/gr1'), {
      name: 'Piso', ownerUid: JEFA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    for (const uid of [JEFA, ALBA, JORGE, ADMIN]) {
      await setDoc(doc(f, `spaces/gr1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
        ...(uid === ADMIN ? { role: 'admin' } : {}),
      });
    }
    await setDoc(doc(f, 'spaces/gr1/manualParticipants/m-tete'), {
      manualId: 'm-tete', displayName: 'Tete', createdByUid: JEFA,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });

    // Sesión del grupo con DOS tickets: Jorge solo participa en el primero.
    await setDoc(doc(f, SG), {
      ownerUid: ALBA, kind: 'multi', name: 'Compra', status: 'open',
      splitModeDefault: 'byItem', shareCode: 'SECRET-CODE-16CHARS',
      currency: 'EUR', contextModelVersion: 1, spaceId: 'gr1',
      computeVersion: 1, totals: { grandTotal: 850 }, balances: {},
    });
    await setDoc(doc(f, `${SG}/participants/p1`), {
      name: 'Alba', isOwner: true, order: 0, claimedByDevice: '',
    });
    await setDoc(doc(f, `${SG}/participants/p2`), {
      name: 'Jorge', isOwner: false, order: 1, claimedByDevice: JORGE,
    });
    await setDoc(doc(f, `${SG}/participants/p3`), {
      name: 'Tete', isOwner: false, order: 2, manualId: 'm-tete',
    });
    await setDoc(doc(f, `${SG}/accounts/a1`), { name: 'Súper', order: 0 });
    for (const [ref, merchant, total] of [
      [T1, 'Familycash', 550],
      [T2, 'Otra tienda', 300],
    ]) {
      await setDoc(doc(f, ref), {
        kind: 'scanned', grandTotal: total, paidByParticipantId: 'p1',
        imagePath: `receipts/sg1/${ref.endsWith('t1') ? 't1' : 't2'}/original.jpg`,
        merchant: { name: merchant }, spaceId: 'gr1', contextModelVersion: 1,
      });
      await setDoc(doc(f, `${ref}/lines/l1`), {
        name: 'Coca-Cola', totalPrice: total, quantityMilli: 1000, order: 0,
        assignment: {
          type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        },
      });
    }

    // Derecho histórico: recompute lo escribiría para el pagador (Alba) y
    // para quien consumió (Jorge). En t2, Jorge NO aparece.
    for (const [tid, uid] of [['t1', ALBA], ['t1', JORGE], ['t2', ALBA]]) {
      await setDoc(doc(f, `${SG}/ticketEntitlements/${tid}_${uid}`), {
        uid, ticketId: tid, accountId: 'a1',
        participantNames: { p1: 'Alba', p2: 'Jorge', p3: 'Tete' },
        grantedAt: serverTimestamp(), schemaVersion: 1,
      });
    }
  });
});

/** Expulsa de verdad: evidencia, bloqueo y borrado en un solo commit. */
async function expulsar(uid) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await deleteDoc(doc(f, `spaces/gr1/members/${uid}`));
    await setDoc(doc(f, `spaces/gr1/entryBlocks/${uid}`), {
      uid, membershipJoinedAt: serverTimestamp(),
      blockedAt: serverTimestamp(), schemaVersion: 1,
    });
  });
}

describe('A11d: lo que conserva un ex-miembro', () => {
  beforeEach(() => expulsar(JORGE));

  it('lee el ticket en el que participó económicamente', () =>
    assertSucceeds(getDoc(doc(db(JORGE), T1))));

  it('y sus líneas, que son el reparto que explica su deuda', () =>
    assertSucceeds(getDocs(collection(db(JORGE), `${T1}/lines`))));

  it('lee su propio derecho, con los nombres de ESE reparto', async () => {
    const snap = await getDoc(
      doc(db(JORGE), `${SG}/ticketEntitlements/t1_${JORGE}`));
    if (!snap.exists()) throw new Error('no puede leer su propio derecho');
    if (snap.data().participantNames.p3 !== 'Tete') {
      throw new Error('sin nombres el reparto es ilegible');
    }
  });

  it('sigue viendo la evidencia de su expulsión', () =>
    assertSucceeds(getDocs(collection(db(JORGE), `${T1}/lines`))));
});

describe('A11d: lo que PIERDE un ex-miembro', () => {
  beforeEach(() => expulsar(JORGE));

  it('no lee un ticket del grupo en el que no participó', () =>
    assertFails(getDoc(doc(db(JORGE), T2))));

  it('ni sus líneas', () =>
    assertFails(getDocs(collection(db(JORGE), `${T2}/lines`))));

  it('no puede LISTAR los tickets del grupo', async () => {
    await assertFails(
      getDocs(collection(db(JORGE), `${SG}/accounts/a1/tickets`)));
    await assertFails(getDocs(collection(db(JORGE), `${SG}/accounts`)));
  });

  it('no lee la sesión (ahí vive el shareCode)', () =>
    assertFails(getDoc(doc(db(JORGE), SG))));

  it('no lee el espacio, sus miembros ni sus manuales', async () => {
    await assertFails(getDoc(doc(db(JORGE), 'spaces/gr1')));
    await assertFails(getDocs(collection(db(JORGE), 'spaces/gr1/members')));
    await assertFails(
      getDocs(collection(db(JORGE), 'spaces/gr1/manualParticipants')));
    // Ni siquiera uno concreto: el nombre histórico de un manual le llega
    // por el DERECHO del ticket (`participantNames`), no abriendo el censo.
    await assertFails(
      getDoc(doc(db(JORGE), 'spaces/gr1/manualParticipants/m-tete')));
  });

  it('no lee el chat', () =>
    assertFails(getDocs(collection(db(JORGE), 'spaces/gr1/messages'))));

  it('no lee los participantes de la sesión', () =>
    assertFails(getDocs(collection(db(JORGE), `${SG}/participants`))));

  it('el derecho es de LECTURA: no escribe ni el ticket ni sus líneas',
    async () => {
      await assertFails(updateDoc(doc(db(JORGE), T1), { grandTotal: 1 }));
      await assertFails(updateDoc(doc(db(JORGE), `${T1}/lines/l1`), {
        name: 'Otro', totalPrice: 1,
      }));
      await assertFails(deleteDoc(doc(db(JORGE), `${T1}/lines/l1`)));
      // Ni siquiera puede reclamar consumo: elegir lo suyo era de miembros.
      await assertFails(updateDoc(doc(db(JORGE), `${T1}/lines/l1`), {
        assignment: {
          type: 'units', schemaVersion: 2,
          units: { u0: { p2: true }, u1: { p2: true } },
        },
      }));
    });

  it('un ADMINISTRADOR expulsado pierde su autoridad de corrección',
    async () => {
      await expulsar(ADMIN);
      await assertFails(updateDoc(doc(db(ADMIN), T1), {
        merchant: { name: 'Corregido' },
        lastEditedByUid: ADMIN, lastEditedAt: serverTimestamp(),
      }));
      // Y sin derecho histórico propio, ni siquiera lo lee.
      await assertFails(getDoc(doc(db(ADMIN), T1)));
    });

  it('nadie puede fabricarse un derecho histórico', async () => {
    for (const actor of [JORGE, ALBA, JEFA, EXTERNO]) {
      await assertFails(setDoc(
        doc(db(actor), `${SG}/ticketEntitlements/t2_${actor}`), {
          uid: actor, ticketId: 't2', accountId: 'a1',
          participantNames: {}, grantedAt: serverTimestamp(),
          schemaVersion: 1,
        }));
    }
  });

  it('un externo no ve nada, ni conociendo la ruta exacta', async () => {
    await assertFails(getDoc(doc(db(EXTERNO), T1)));
    await assertFails(getDocs(collection(db(EXTERNO), `${T1}/lines`)));
    await assertFails(getDoc(
      doc(db(EXTERNO), `${SG}/ticketEntitlements/t1_${JORGE}`)));
  });
});

describe('A11d: el miembro ACTIVO no pierde nada (A11b intacto)', () => {
  it('sigue auditando todos los tickets del grupo', async () => {
    const f = db(JORGE);
    await assertSucceeds(getDoc(doc(f, T1)));
    await assertSucceeds(getDoc(doc(f, T2)));
    await assertSucceeds(getDocs(collection(f, `${SG}/accounts`)));
    await assertSucceeds(getDocs(collection(f, `${SG}/participants`)));
  });

  it('y el dueño de la sesión conserva su lectura completa', async () => {
    const f = db(ALBA);
    await assertSucceeds(getDoc(doc(f, SG)));
    await assertSucceeds(getDoc(doc(f, T2)));
  });
});
