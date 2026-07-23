/**
 * Tests de la matriz de autorización de ESPECIFICACION.md §13.2 contra el
 * Emulator Suite. Cada celda de la matriz tiene su caso positivo y negativo.
 *
 * Ejecutar desde la raíz del repo (levanta el emulador, ejecuta y lo apaga):
 *   firebase emulators:exec --only firestore --project demo-salda \
 *     "npm --prefix backend/firestore test"
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
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let env;

const OWNER = 'owner-uid';
const GUEST = 'guest-uid'; // anónimo con guestAccess concedido
const OTHER = 'other-guest-uid'; // anónimo que reclamó p3
const STRANGER = 'stranger-uid'; // autenticado SIN guestAccess
const UNVERIFIED = 'unverified-owner-uid';
const SOCIAL_OUTSIDER = 'social-outsider-uid';
const THIRD = 'third-uid'; // verificado con perfil, invitado a sp1 (P4)
const FOURTH = 'fourth-uid'; // verificado con perfil, sin relación con sp1
const CODE = 'SECRET-CODE-16CHARS';

const authClaims = (uid) =>
  [GUEST, OTHER].includes(uid)
    ? { firebase: { sign_in_provider: 'anonymous' } }
    : {
        email: `${uid}@salda.test`,
        email_verified: uid !== UNVERIFIED,
        firebase: { sign_in_provider: 'password' },
      };

const db = (uid) =>
  uid === null
    ? env.unauthenticatedContext().firestore()
    : env.authenticatedContext(uid, authClaims(uid)).firestore();

const S = 'sessions/s1';

const friendshipId = (firstUid, secondUid) => {
  const members = [firstUid, secondUid].sort();
  const serialized = members.map((uid) => `${[...uid].length}:${uid}`).join('');
  return Buffer.from(serialized, 'utf8').toString('hex');
};

const friendshipData = (requesterUid, receiverUid, overrides = {}) => ({
  memberUids: [requesterUid, receiverUid].sort(),
  requesterUid,
  receiverUid,
  status: 'pending',
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  schemaVersion: 1,
  ...overrides,
});

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, S), {
      ownerUid: OWNER,
      kind: 'multi',
      name: 'Viaje a Madrid',
      status: 'open',
      splitModeDefault: 'byItem',
      shareCode: CODE,
      currency: 'EUR',
      computeVersion: 0,
      totals: { grandTotal: 0 },
      balances: {},
    });
    await setDoc(doc(f, `${S}/guestAccess/${GUEST}`), { shareCode: CODE });
    await setDoc(doc(f, `${S}/guestAccess/${OTHER}`), { shareCode: CODE });
    await setDoc(doc(f, `${S}/participants/p1`), {
      name: 'Edgar', isOwner: true, claimedByDevice: '',
    });
    await setDoc(doc(f, `${S}/participants/p2`), {
      name: 'Alba', isOwner: false, claimedByDevice: GUEST,
    });
    await setDoc(doc(f, `${S}/participants/p3`), {
      name: 'Lucía', isOwner: false, claimedByDevice: OTHER,
    });
    await setDoc(doc(f, `${S}/participants/p4`), {
      name: 'Mario', isOwner: false, claimedByDevice: '',
    });
    await setDoc(doc(f, `${S}/accounts/a1`), { name: 'Hotel', order: 0 });
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t1`), {
      kind: 'manual', grandTotal: 1000, paidByParticipantId: 'p1',
    });
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t1/lines/l1`), {
      name: 'Cena', totalPrice: 1000,
      assignment: { type: 'unassigned', participants: {} },
    });
    // Línea con 2 unidades (P2.1): el peso reclama unidades.
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t1/lines/l3`), {
      name: 'Flautas', totalPrice: 400, quantityMilli: 2000,
      assignment: { type: 'unassigned', participants: {} },
    });
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t1/lines/l4`), {
      name: 'Pizzas', totalPrice: 800, quantityMilli: 2000,
      unitIds: ['u0', 'u1'],
      assignment: { type: 'units', schemaVersion: 2, units: {} },
    });
    // Ticket con modo forzado a "a medias": el invitado NO puede autoasignarse.
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t2`), {
      kind: 'manual', grandTotal: 500, paidByParticipantId: 'p1',
      splitModeOverride: 'equal',
    });
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t2/lines/l1`), {
      name: 'Taxi', totalPrice: 500,
      assignment: { type: 'unassigned', participants: {} },
    });
    await setDoc(doc(f, `${S}/settlements/st1`), {
      from: 'p2', to: 'p1', amount: 500, state: 'pending',
    });
    await setDoc(doc(f, `${S}/settlements/st2`), {
      from: 'p3', to: 'p1', amount: 300, state: 'pending',
    });
    // P2.1: liquidación cuyo receptor es un invitado RECLAMADO (p2=GUEST).
    await setDoc(doc(f, `${S}/settlements/st3`), {
      from: 'p3', to: 'p2', amount: 500, state: 'marked',
    });
    // P2.1: receptor sin reclamar (p4): el owner actúa de representante.
    await setDoc(doc(f, `${S}/settlements/st4`), {
      from: 'p2', to: 'p4', amount: 200, state: 'marked',
    });
    // Sesión cerrada para probar el bloqueo total.
    await setDoc(doc(f, 'sessions/s2'), {
      ownerUid: OWNER, kind: 'single', name: 'Cerrada', status: 'closed',
      splitModeDefault: 'equal', shareCode: CODE, currency: 'EUR',
      computeVersion: 3,
    });
    await setDoc(doc(f, 'sessions/s2/participants/p1'), {
      name: 'Edgar', isOwner: true, claimedByDevice: '',
    });
    await setDoc(doc(f, 'sessions/s3'), {
      ownerUid: UNVERIFIED, kind: 'single', name: 'Cuenta anterior',
      status: 'open', splitModeDefault: 'equal', shareCode: CODE,
      currency: 'EUR', computeVersion: 1,
    });
    await setDoc(doc(f, 'sessions/s3/participants/p1'), {
      name: 'Pendiente', isOwner: true, claimedByDevice: '',
    });
    await setDoc(doc(f, 'users/owner-uid'), { displayName: 'Edgar' });
    // Identidad pública ya existente (P2): perfil + claim de username.
    await setDoc(doc(f, `profiles/${STRANGER}`), {
      displayName: 'Alba García', displayNameLower: 'alba garcia',
      username: 'alba', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(), schemaVersion: 1,
    });
    await setDoc(doc(f, 'usernames/alba'), {
      uid: STRANGER, createdAt: serverTimestamp(),
    });
    // P4: perfiles adicionales y espacios de prueba. El propietario de los
    // espacios sembrados es SOCIAL_OUTSIDER (verificado CON perfil); OWNER
    // se mantiene sin perfil para no interferir con los tests de P2.
    for (const [uid, username] of [
      [THIRD, 'tercero'], [FOURTH, 'cuarto'],
    ]) {
      await setDoc(doc(f, `profiles/${uid}`), {
        displayName: username, displayNameLower: username,
        username, createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(), schemaVersion: 1,
      });
      await setDoc(doc(f, `usernames/${username}`), {
        uid, createdAt: serverTimestamp(),
      });
    }
    // sp1: activo; SOCIAL_OUTSIDER propietario, STRANGER y OWNER miembros.
    await setDoc(doc(f, 'spaces/sp1'), {
      name: 'Viaje', ownerUid: SOCIAL_OUTSIDER, status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    await setDoc(doc(f, 'spaces/sp1/members/' + SOCIAL_OUTSIDER), {
      uid: SOCIAL_OUTSIDER, joinedAt: serverTimestamp(),
    });
    await setDoc(doc(f, 'spaces/sp1/members/' + STRANGER), {
      uid: STRANGER, joinedAt: serverTimestamp(),
    });
    await setDoc(doc(f, 'spaces/sp1/members/' + OWNER), {
      uid: OWNER, joinedAt: serverTimestamp(),
    });
    // sp2: archivado (mismo owner).
    await setDoc(doc(f, 'spaces/sp2'), {
      name: 'Antiguo', ownerUid: SOCIAL_OUTSIDER, status: 'archived',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    await setDoc(doc(f, 'spaces/sp2/members/' + SOCIAL_OUTSIDER), {
      uid: SOCIAL_OUTSIDER, joinedAt: serverTimestamp(),
    });
    // Invitación pendiente a THIRD para sp1.
    await setDoc(doc(f, `spaceInvites/sp1_${THIRD}`), {
      spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
      toUid: THIRD, status: 'pending', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    // Ticket ya vinculado a sp1 (lectura de miembros vía collection group).
    await setDoc(doc(f, `${S}/accounts/a1/tickets/t3`), {
      kind: 'manual', grandTotal: 700, paidByParticipantId: 'p1',
      spaceId: 'sp1', merchant: { name: 'Cena grupo' },
    });
  });
}

async function seedSocialProfiles() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, `profiles/${OWNER}`), {
      displayName: 'Edgar', displayNameLower: 'edgar', username: 'edgar',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), schemaVersion: 1,
    });
    await setDoc(doc(f, `profiles/${SOCIAL_OUTSIDER}`), {
      displayName: 'Pedro', displayNameLower: 'pedro', username: 'pedro',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), schemaVersion: 1,
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-salda',
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
});

after(async () => env.cleanup());

beforeEach(seed);

// ─── Identidad pública (P2): profiles + usernames ───────────────────────
describe('profiles/usernames', () => {
  const profileData = (username, overrides = {}) => ({
    displayName: 'Edgar Cantera',
    displayNameLower: 'edgar cantera',
    username,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  // Alta atómica: perfil + claim en el MISMO batch (como hace la app).
  const createProfile = (f, uid, username, overrides = {}) => {
    const batch = writeBatch(f);
    batch.set(doc(f, `profiles/${uid}`), profileData(username, overrides));
    batch.set(doc(f, `usernames/${username}`), {
      uid, createdAt: serverTimestamp(),
    });
    return batch.commit();
  };

  it('cuenta verificada crea perfil + claim en batch', () =>
    assertSucceeds(createProfile(db(OWNER), OWNER, 'edgar')));

  it('invitado anónimo no tiene perfil público', () =>
    assertFails(createProfile(db(GUEST), GUEST, 'invitadin')));

  it('cuenta de correo sin verificar no crea perfil', () =>
    assertFails(createProfile(db(UNVERIFIED), UNVERIFIED, 'pendiente')));

  it('no se puede crear un perfil a nombre de otro', () =>
    assertFails(createProfile(db(OWNER), 'otro-uid', 'suplantado')));

  it('perfil sin claim en el mismo batch: denegado', () =>
    assertFails(setDoc(doc(db(OWNER), `profiles/${OWNER}`),
      profileData('edgar'))));

  it('claim sin perfil que lo referencie: denegado', () =>
    assertFails(setDoc(doc(db(OWNER), 'usernames/edgar'),
      { uid: OWNER, createdAt: serverTimestamp() })));

  it('claim con uid ajeno: denegado', async () => {
    const f = db(OWNER);
    const batch = writeBatch(f);
    batch.set(doc(f, `profiles/${OWNER}`), profileData('edgar'));
    batch.set(doc(f, 'usernames/edgar'),
      { uid: 'otro-uid', createdAt: serverTimestamp() });
    await assertFails(batch.commit());
  });

  it('usernames inválidos o reservados: denegados', async () => {
    for (const bad of ['Edgar', 'ed', 'ed__gar', 'edgar_', '9edgar', 'admin', 'salda']) {
      await assertFails(createProfile(db(OWNER), OWNER, bad));
    }
  });

  it('username ya ocupado: denegado', () =>
    assertFails(createProfile(db(OWNER), OWNER, 'alba')));

  it('campos extra en el perfil (p. ej. bio): denegados hasta su fase', () =>
    assertFails(createProfile(db(OWNER), OWNER, 'edgar',
      { bio: 'hola' })));

  it('cualquier autenticado lee y busca perfiles; sin autenticar no', async () => {
    await assertSucceeds(getDoc(doc(db(GUEST), `profiles/${STRANGER}`)));
    await assertSucceeds(getDocs(query(
      collection(db(GUEST), 'profiles'),
      where('username', '>=', 'al'), where('username', '<=', 'al'))));
    await assertSucceeds(getDoc(doc(db(GUEST), 'usernames/alba')));
    await assertFails(getDoc(doc(db(null), `profiles/${STRANGER}`)));
  });

  it('el dueño edita displayName conservando su username', () =>
    assertSucceeds(updateDoc(doc(db(STRANGER), `profiles/${STRANGER}`), {
      displayName: 'Alba G.', displayNameLower: 'alba g',
      updatedAt: serverTimestamp(),
    })));

  it('cambio de username: batch libera el viejo y reclama el nuevo', async () => {
    const f = db(STRANGER);
    const batch = writeBatch(f);
    batch.delete(doc(f, 'usernames/alba'));
    batch.set(doc(f, 'usernames/alba_garcia'),
      { uid: STRANGER, createdAt: serverTimestamp() });
    batch.update(doc(f, `profiles/${STRANGER}`), {
      username: 'alba_garcia', updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('cambiar el username del perfil SIN reclamar el claim: denegado', () =>
    assertFails(updateDoc(doc(db(STRANGER), `profiles/${STRANGER}`), {
      username: 'alba_garcia', updatedAt: serverTimestamp(),
    })));

  it('createdAt es inmutable', () =>
    assertFails(updateDoc(doc(db(STRANGER), `profiles/${STRANGER}`), {
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    })));

  it('nadie borra ni modifica el claim de otro', async () => {
    await assertFails(deleteDoc(doc(db(OWNER), 'usernames/alba')));
    await assertFails(updateDoc(doc(db(STRANGER), 'usernames/alba'),
      { uid: STRANGER }));
  });
});

// ─── Amistades (P3): relación canónica por pareja UID ─────────────────
describe('friendships', () => {
  beforeEach(seedSocialProfiles);

  const id = () => friendshipId(OWNER, STRANGER);
  const refFor = (uid = OWNER) => doc(db(uid), `friendships/${id()}`);

  it('una cuenta completa con perfil crea una solicitud canónica', async () => {
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    const saved = await getDoc(refFor());
    assert.equal(saved.data().status, 'pending');
    assert.deepEqual(saved.data().memberUids, [OWNER, STRANGER].sort());
  });

  // Regresión: el cliente envía la solicitud dentro de una transacción que
  // primero LEE el documento (aún inexistente). La regla de get debe admitir
  // esa lectura o la transacción entera muere con permission-denied.
  it('el flujo real del cliente: transacción que lee el doc inexistente y lo crea',
      async () => {
    const database = db(OWNER);
    await assertSucceeds(runTransaction(database, async (tx) => {
      const snapshot = await tx.get(doc(database, `friendships/${id()}`));
      assert.equal(snapshot.exists(), false);
      tx.set(
        doc(database, `friendships/${id()}`),
        friendshipData(OWNER, STRANGER),
      );
    }));
    const saved = await getDoc(refFor());
    assert.equal(saved.data().status, 'pending');
  });

  it('get de una relación inexistente: solo si el ID incluye al lector',
      async () => {
    await assertSucceeds(getDoc(refFor(OWNER)));
    await assertSucceeds(getDoc(refFor(STRANGER)));
    // Cuenta social válida pero ajena al par: no puede sondear existencia.
    await assertFails(getDoc(refFor(SOCIAL_OUTSIDER)));
    await assertFails(getDoc(refFor(GUEST)));
  });

  it('solo los participantes completos leen y la query exige arrayContains',
      async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `friendships/${id()}`),
      { ...friendshipData(OWNER, STRANGER), createdAt: new Date(), updatedAt: new Date() },
    ));
    await assertSucceeds(getDoc(refFor(OWNER)));
    await assertSucceeds(getDoc(refFor(STRANGER)));
    await assertFails(getDoc(refFor(SOCIAL_OUTSIDER)));
    await assertFails(getDoc(refFor(GUEST)));
    await assertSucceeds(getDocs(query(
      collection(db(OWNER), 'friendships'),
      where('memberUids', 'array-contains', OWNER),
    )));
    await assertFails(getDocs(collection(db(OWNER), 'friendships')));
  });

  it('el receptor acepta sin poder alterar la identidad del vínculo', async () => {
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    await assertSucceeds(updateDoc(refFor(STRANGER), {
      status: 'friends', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(refFor(OWNER), {
      status: 'pending', updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(refFor(STRANGER), {
      requesterUid: STRANGER,
      status: 'friends', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  it('solo el receptor acepta; emisor y tercero no', async () => {
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    const change = {
      status: 'friends', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    };
    await assertFails(updateDoc(refFor(OWNER), change));
    await assertFails(updateDoc(refFor(SOCIAL_OUTSIDER), change));
  });

  it('emisor cancela, receptor rechaza y roles ajenos no borran', async () => {
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    await assertFails(deleteDoc(refFor(SOCIAL_OUTSIDER)));
    await assertSucceeds(deleteDoc(refFor(OWNER)));
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    await assertSucceeds(deleteDoc(refFor(STRANGER)));
  });

  it('cualquiera de los dos elimina la amistad y después se puede reenviar',
      async () => {
    await assertSucceeds(setDoc(refFor(), friendshipData(OWNER, STRANGER)));
    await assertSucceeds(updateDoc(refFor(STRANGER), {
      status: 'friends', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(deleteDoc(refFor(OWNER)));
    await assertSucceeds(setDoc(refFor(STRANGER), friendshipData(STRANGER, OWNER)));
  });

  it('deniega anónimo, pendiente, cuenta sin perfil y suplantación', async () => {
    await assertFails(setDoc(refFor(GUEST), friendshipData(GUEST, STRANGER)));
    await assertFails(setDoc(refFor(UNVERIFIED), friendshipData(UNVERIFIED, STRANGER)));
    await assertFails(setDoc(refFor(), friendshipData(STRANGER, OWNER)));
    const noProfileId = friendshipId('verified-no-profile', STRANGER);
    await assertFails(setDoc(
      doc(db('verified-no-profile'), `friendships/${noProfileId}`),
      friendshipData('verified-no-profile', STRANGER),
    ));
  });

  it('deniega auto-solicitud, ID alternativo, miembros desordenados y extra',
      async () => {
    const selfId = friendshipId(OWNER, OWNER + '-other');
    await assertFails(setDoc(
      doc(db(OWNER), `friendships/${selfId}`),
      friendshipData(OWNER, OWNER, { memberUids: [OWNER, OWNER] }),
    ));
    await assertFails(setDoc(
      doc(db(OWNER), 'friendships/no-canonico'),
      friendshipData(OWNER, STRANGER),
    ));
    await assertFails(setDoc(refFor(), friendshipData(OWNER, STRANGER, {
      memberUids: [STRANGER, OWNER],
    })));
    await assertFails(setDoc(refFor(), friendshipData(OWNER, STRANGER, {
      unexpected: true,
    })));
  });

  it('deniega crear amistad directa, timestamps falsos y receptor sin perfil',
      async () => {
    await assertFails(setDoc(refFor(), friendshipData(OWNER, STRANGER, {
      status: 'friends', acceptedAt: serverTimestamp(),
    })));
    await assertFails(setDoc(refFor(), friendshipData(OWNER, STRANGER, {
      createdAt: new Date(0), updatedAt: new Date(0),
    })));
    const missing = 'missing-profile-uid';
    await assertFails(setDoc(
      doc(db(OWNER), `friendships/${friendshipId(OWNER, missing)}`),
      friendshipData(OWNER, missing),
    ));
  });

  it('invitados y no verificados no actualizan ni eliminan relaciones',
      async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `friendships/${id()}`),
      { ...friendshipData(OWNER, STRANGER), createdAt: new Date(), updatedAt: new Date() },
    ));
    await assertFails(updateDoc(refFor(GUEST), {
      status: 'friends', acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(deleteDoc(refFor(UNVERIFIED)));
  });
});

// ─── Sesiones: crear ────────────────────────────────────────────────────
describe('sessions.create', () => {
  const valid = {
    ownerUid: OWNER, kind: 'single', name: 'Cena', status: 'open',
    splitModeDefault: 'equal', shareCode: 'OTRO-CODIGO-16CH', currency: 'EUR',
    computeVersion: 0,
  };

  it('owner crea una sesión válida', () =>
    assertSucceeds(setDoc(doc(db(OWNER), 'sessions/nueva'), valid)));

  it('sesión contextual exige un espacio del que el owner sea miembro',
      async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), 'sessions/contextual'), {
      ...valid, contextModelVersion: 1, spaceId: 'sp1', spaceName: 'Viaje',
    }));
    await assertFails(setDoc(doc(db(FOURTH), 'sessions/contextual-ajena'), {
      ...valid, ownerUid: FOURTH, contextModelVersion: 1,
      spaceId: 'sp1', spaceName: 'Viaje',
    }));
  });

  it('invitado móvil crea una sesión propia', () =>
    assertSucceeds(setDoc(doc(db(GUEST), 'sessions/nueva'),
      { ...valid, ownerUid: GUEST })));

  it('cuenta de correo sin verificar no crea sesiones', () =>
    assertFails(setDoc(doc(db(UNVERIFIED), 'sessions/nueva'),
      { ...valid, ownerUid: UNVERIFIED })));

  it('no se puede crear a nombre de otro', () =>
    assertFails(setDoc(doc(db(STRANGER), 'sessions/nueva'), valid)));

  it('no se puede crear ya cerrada', () =>
    assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, status: 'closed' })));

  it('shareCode corto rechazado', () =>
    assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, shareCode: 'corto' })));

  it('computeVersion distinto de 0 rechazado (agregados son de la function)', () =>
    assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, computeVersion: 7 })));

  it('agregados iniciales manipulados: denegado', async () => {
    await assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, totals: { grandTotal: 1 } }));
    await assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, balances: { p1: { net: 1 } } }));
    await assertFails(setDoc(doc(db(OWNER), 'sessions/nueva'),
      { ...valid, pendingSettlements: 1 }));
  });

  it('sin autenticar: denegado', () =>
    assertFails(setDoc(doc(db(null), 'sessions/nueva'), valid)));
});

// ─── Sesiones: leer / actualizar / borrar ───────────────────────────────
describe('sessions.read/update/delete', () => {
  it('owner lee y lista sus sesiones', async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), S)));
    await assertSucceeds(getDocs(query(
      collection(db(OWNER), 'sessions'), where('ownerUid', '==', OWNER))));
  });

  it('cuenta sin verificar conserva lectura de sus datos existentes', async () => {
    await assertSucceeds(getDoc(doc(db(UNVERIFIED), 'sessions/s3')));
    await assertSucceeds(getDoc(
      doc(db(UNVERIFIED), 'sessions/s3/participants/p1')));
  });

  it('cuenta sin verificar no modifica ni borra sus sesiones', async () => {
    await assertFails(updateDoc(doc(db(UNVERIFIED), 'sessions/s3'),
      { name: 'Cambio bloqueado' }));
    await assertFails(setDoc(
      doc(db(UNVERIFIED), 'sessions/s3/participants/p2'),
      { name: 'Bloqueado', isOwner: false }));
    await assertFails(deleteDoc(doc(db(UNVERIFIED), 'sessions/s3')));
  });

  it('invitado con guestAccess lee la sesión', () =>
    assertSucceeds(getDoc(doc(db(GUEST), S))));

  it('autenticado SIN guestAccess no lee', () =>
    assertFails(getDoc(doc(db(STRANGER), S))));

  it('owner edita contenido con la sesión abierta', () =>
    assertSucceeds(updateDoc(doc(db(OWNER), S), { name: 'Madrid 2026' })));

  it('owner NO puede tocar agregados (totals/balances/computeVersion)', async () => {
    await assertFails(updateDoc(doc(db(OWNER), S),
      { totals: { grandTotal: 999999 } }));
    await assertFails(updateDoc(doc(db(OWNER), S), { computeVersion: 99 }));
  });

  it('invitado no puede editar la sesión', () =>
    assertFails(updateDoc(doc(db(GUEST), S), { name: 'hack' })));

  it('cerrada: contenido bloqueado, pero el owner puede reabrir', async () => {
    await assertFails(updateDoc(doc(db(OWNER), 'sessions/s2'),
      { name: 'nuevo nombre' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), 'sessions/s2'),
      { status: 'open' }));
  });

  it('solo el owner borra la sesión', async () => {
    await assertFails(deleteDoc(doc(db(GUEST), S)));
    await assertSucceeds(deleteDoc(doc(db(OWNER), S)));
  });
});

// ─── guestAccess: prueba de conocimiento del shareCode ──────────────────
describe('guestAccess', () => {
  it('con el código correcto se concede acceso', () =>
    assertSucceeds(setDoc(
      doc(db(STRANGER), `${S}/guestAccess/${STRANGER}`),
      { shareCode: CODE })));

  it('con código incorrecto: denegado', () =>
    assertFails(setDoc(
      doc(db(STRANGER), `${S}/guestAccess/${STRANGER}`),
      { shareCode: 'CODIGO-EQUIVOCADO' })));

  it('no se puede crear el guestAccess de OTRO uid', () =>
    assertFails(setDoc(
      doc(db(STRANGER), `${S}/guestAccess/otra-persona`),
      { shareCode: CODE })));

  it('en sesión cerrada no se conceden accesos nuevos', () =>
    assertFails(setDoc(
      doc(db(STRANGER), `sessions/s2/guestAccess/${STRANGER}`),
      { shareCode: CODE })));

  it('el owner puede revocar accesos', () =>
    assertSucceeds(deleteDoc(doc(db(OWNER), `${S}/guestAccess/${GUEST}`))));
});

// ─── Participantes ───────────────────────────────────────────────────────
describe('participants', () => {
  it('owner crea y borra participantes (abierta)', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), `${S}/participants/p9`),
      { name: 'Nuevo', isOwner: false, claimedByDevice: '' }));
    await assertSucceeds(deleteDoc(doc(db(OWNER), `${S}/participants/p9`)));
  });

  it('en sesión cerrada el owner tampoco crea participantes', () =>
    assertFails(setDoc(doc(db(OWNER), 'sessions/s2/participants/p9'),
      { name: 'Nuevo', isOwner: false, claimedByDevice: '' })));

  it('invitado reclama un nombre LIBRE', () =>
    assertSucceeds(updateDoc(doc(db(GUEST), `${S}/participants/p4`),
      { claimedByDevice: GUEST })));

  it('invitado NO reclama un nombre ya reclamado por otro', () =>
    assertFails(updateDoc(doc(db(GUEST), `${S}/participants/p3`),
      { claimedByDevice: GUEST })));

  it('invitado libera SU nombre pero no el de otro', async () => {
    await assertSucceeds(updateDoc(doc(db(GUEST), `${S}/participants/p2`),
      { claimedByDevice: '' }));
    await assertFails(updateDoc(doc(db(GUEST), `${S}/participants/p3`),
      { claimedByDevice: '' }));
  });

  it('invitado no puede tocar otros campos del participante', () =>
    assertFails(updateDoc(doc(db(GUEST), `${S}/participants/p2`),
      { name: 'Renombrada' })));

  it('lectura: invitado sí, extraño no', async () => {
    await assertSucceeds(getDoc(doc(db(GUEST), `${S}/participants/p1`)));
    await assertFails(getDoc(doc(db(STRANGER), `${S}/participants/p1`)));
  });
});

// ─── Cuentas y tickets ───────────────────────────────────────────────────
describe('accounts & tickets', () => {
  it('owner crea cuenta (sin agregados) y ticket válido', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), `${S}/accounts/a2`),
      { name: 'Gasolina', order: 1 }));
    await assertSucceeds(setDoc(doc(db(OWNER), `${S}/accounts/a2/tickets/t1`),
      { kind: 'scanned', grandTotal: 4830, paidByParticipantId: 'p2' }));
  });

  it('cuenta con "totals" del cliente: denegada (solo function)', () =>
    assertFails(setDoc(doc(db(OWNER), `${S}/accounts/a2`),
      { name: 'Gasolina', totals: { grandTotal: 1 } })));

  it('ticket con grandTotal no entero: denegado', () =>
    assertFails(setDoc(doc(db(OWNER), `${S}/accounts/a1/tickets/t9`),
      { kind: 'manual', grandTotal: '10€', paidByParticipantId: 'p1' })));

  it('invitado no escribe cuentas ni tickets', async () => {
    await assertFails(setDoc(doc(db(GUEST), `${S}/accounts/a9`),
      { name: 'x' }));
    await assertFails(updateDoc(doc(db(GUEST), `${S}/accounts/a1/tickets/t1`),
      { grandTotal: 1 }));
  });
});

// ─── Líneas: autoasignación del invitado ────────────────────────────────
describe('lines: autoasignación', () => {
  const line = `${S}/accounts/a1/tickets/t1/lines/l1`;

  it('invitado se asigna a sí mismo (byItem, abierta, peso 1)', () =>
    assertSucceeds(updateDoc(doc(db(GUEST), line), {
      assignment: { type: 'one', participants: { p2: 1 }, lastEditorPid: 'p2' },
    })));

  it('invitado se quita de la línea', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), line), {
        assignment: { type: 'shared', participants: { p2: 1, p3: 1 } },
      }));
    await assertSucceeds(updateDoc(doc(db(GUEST), line), {
      assignment: { type: 'shared', participants: { p3: 1 }, lastEditorPid: 'p2' },
    }));
  });

  it('no puede tocar la entrada de OTRO participante', () =>
    assertFails(updateDoc(doc(db(GUEST), line), {
      assignment: { type: 'shared', participants: { p3: 1 }, lastEditorPid: 'p3' },
    })));

  it('no puede colar más claves que la suya', () =>
    assertFails(updateDoc(doc(db(GUEST), line), {
      assignment: {
        type: 'shared',
        participants: { p2: 1, p1: 1 },
        lastEditorPid: 'p2',
      },
    })));

  it('peso distinto de 1: denegado (los pesos los pone el owner)', () =>
    assertFails(updateDoc(doc(db(GUEST), line), {
      assignment: { type: 'one', participants: { p2: 5 }, lastEditorPid: 'p2' },
    })));

  it('no puede convertir la línea en "todos"', () =>
    assertFails(updateDoc(doc(db(GUEST), line), {
      assignment: { type: 'all', participants: { p2: 1 }, lastEditorPid: 'p2' },
    })));

  it('en ticket con modo "a medias" no hay autoasignación', () =>
    assertFails(updateDoc(
      doc(db(GUEST), `${S}/accounts/a1/tickets/t2/lines/l1`), {
        assignment: { type: 'one', participants: { p2: 1 }, lastEditorPid: 'p2' },
      })));

  it('no puede tocar otros campos de la línea', () =>
    assertFails(updateDoc(doc(db(GUEST), line),
      { totalPrice: 1, assignment: { type: 'one', participants: { p2: 1 }, lastEditorPid: 'p2' } })));

  it('owner asigna libremente', () =>
    assertSucceeds(updateDoc(doc(db(OWNER), line), {
      assignment: { type: 'shared', participants: { p1: 2, p2: 1 } },
    })));

  const unitsLine = `${S}/accounts/a1/tickets/t1/lines/l3`;

  it('P2.1: en una línea de 2 unidades el invitado reclama 1 o 2', async () => {
    await assertSucceeds(updateDoc(doc(db(GUEST), unitsLine), {
      assignment: { type: 'one', participants: { p2: 1 }, lastEditorPid: 'p2' },
    }));
    await assertSucceeds(updateDoc(doc(db(GUEST), unitsLine), {
      assignment: { type: 'one', participants: { p2: 2 }, lastEditorPid: 'p2' },
    }));
  });

  it('P2.1: no puede reclamar más unidades de las que tiene la línea', () =>
    assertFails(updateDoc(doc(db(GUEST), unitsLine), {
      assignment: { type: 'one', participants: { p2: 3 }, lastEditorPid: 'p2' },
    })));

  it('P2.1: el peso debe ser entero', () =>
    assertFails(updateDoc(doc(db(GUEST), unitsLine), {
      assignment: {
        type: 'one', participants: { p2: 1.5 }, lastEditorPid: 'p2',
      },
    })));

  const unitLine = `${S}/accounts/a1/tickets/t1/lines/l4`;

  it('P2.2: dos participantes comparten la misma unidad sin pisarse', async () => {
    await assertSucceeds(updateDoc(doc(db(GUEST), unitLine), {
      assignment: {
        type: 'units', schemaVersion: 2,
        units: { u0: { p2: true } },
        lastEditorPid: 'p2', lastEditedUnit: 'u0',
      },
    }));
    await assertSucceeds(updateDoc(doc(db(OTHER), unitLine), {
      assignment: {
        type: 'units', schemaVersion: 2,
        units: { u0: { p2: true, p3: true } },
        lastEditorPid: 'p3', lastEditedUnit: 'u0',
      },
    }));
    const saved = await getDoc(doc(db(GUEST), unitLine));
    assert.deepEqual(saved.data().assignment.units.u0, { p2: true, p3: true });
  });

  it('P2.2: invitado solo cambia su entrada y una unidad válida', async () => {
    await assertFails(updateDoc(doc(db(GUEST), unitLine), {
      assignment: {
        type: 'units', schemaVersion: 2,
        units: { u0: { p3: true } },
        lastEditorPid: 'p2', lastEditedUnit: 'u0',
      },
    }));
    await assertFails(updateDoc(doc(db(GUEST), unitLine), {
      assignment: {
        type: 'units', schemaVersion: 2,
        units: { u9: { p2: true } },
        lastEditorPid: 'p2', lastEditedUnit: 'u9',
      },
    }));
    await assertFails(updateDoc(doc(db(GUEST), unitLine), {
      assignment: {
        type: 'units', schemaVersion: 2,
        units: { u0: { p2: true }, u1: { p2: true } },
        lastEditorPid: 'p2', lastEditedUnit: 'u0',
      },
    }));
  });

  it('P2.2: un invitado no convierte por su cuenta un reparto histórico', () =>
    assertFails(updateDoc(doc(db(GUEST), unitsLine), {
      assignment: {
        type: 'units', schemaVersion: 2, units: { u0: { p2: true } },
        lastEditorPid: 'p2', lastEditedUnit: 'u0',
      },
    })));
});

// ─── Liquidaciones ───────────────────────────────────────────────────────
describe('settlements', () => {
  it('el owner crea/borra liquidaciones (import de backup, RF-91); el invitado NO',
      async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), `${S}/settlements/st9`),
      { from: 'p2', to: 'p1', amount: 1, state: 'pending' }));
    await assertSucceeds(deleteDoc(doc(db(OWNER), `${S}/settlements/st9`)));
    // Forma inválida: denegada.
    await assertFails(setDoc(doc(db(OWNER), `${S}/settlements/st8`),
      { from: 'p2', to: 'p1', amount: -5, state: 'pending' }));
    // Invitados jamás.
    await assertFails(setDoc(doc(db(GUEST), `${S}/settlements/st7`),
      { from: 'p2', to: 'p1', amount: 1, state: 'pending' }));
    await assertFails(deleteDoc(doc(db(GUEST), `${S}/settlements/st1`)));
  });

  it('el deudor marca la SUYA como pagada (pending→marked)', () =>
    assertSucceeds(updateDoc(doc(db(GUEST), `${S}/settlements/st1`),
      { state: 'marked' })));

  it('no puede marcar la de otro', () =>
    assertFails(updateDoc(doc(db(GUEST), `${S}/settlements/st2`),
      { state: 'marked' })));

  it('el invitado no confirma (eso es del acreedor/owner)', () =>
    assertFails(updateDoc(doc(db(GUEST), `${S}/settlements/st1`),
      { state: 'confirmed' })));

  it('el owner confirma la SUYA (él es el receptor) y puede deshacerla',
      async () => {
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st1`),
      { state: 'confirmed' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st1`),
      { state: 'pending' }));
  });

  it('P2.1: el receptor reclamado confirma la recepción y puede deshacerla',
      async () => {
    // st3: p3 → p2; p2 está reclamado por GUEST. Solo GUEST confirma.
    await assertSucceeds(updateDoc(doc(db(GUEST), `${S}/settlements/st3`),
      { state: 'confirmed' }));
    await assertSucceeds(updateDoc(doc(db(GUEST), `${S}/settlements/st3`),
      { state: 'pending' }));
  });

  it('P2.1: el CREADOR no confirma cuando el receptor está reclamado', () =>
    assertFails(updateDoc(doc(db(OWNER), `${S}/settlements/st3`),
      { state: 'confirmed' })));

  it('P2.1: el deudor tampoco confirma la que él debe', () =>
    // st3: OTHER reclama p3 (el deudor); no es el receptor.
    assertFails(updateDoc(doc(db(OTHER), `${S}/settlements/st3`),
      { state: 'confirmed' })));

  it('P2.1: receptor sin reclamar → el owner actúa como representante',
      async () => {
    // st4: p2 → p4; p4 no está reclamado por ningún dispositivo.
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st4`),
      { state: 'confirmed' }));
    // El deudor (GUEST reclama p2) sigue sin poder confirmar.
    await assertFails(updateDoc(doc(db(GUEST), `${S}/settlements/st4`),
      { state: 'confirmed' }));
  });

  it('P2.1: el owner mantiene la gestión pending ↔ marked', async () => {
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st3`),
      { state: 'pending' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st3`),
      { state: 'marked' }));
  });

  it('nadie cambia importe/from/to', async () => {
    await assertFails(updateDoc(doc(db(OWNER), `${S}/settlements/st1`),
      { amount: 1 }));
    await assertFails(updateDoc(doc(db(GUEST), `${S}/settlements/st1`),
      { state: 'marked', amount: 1 }));
  });
});

// ─── Actividad ───────────────────────────────────────────────────────────
describe('activity', () => {
  it('owner e invitado añaden eventos; nadie los edita o borra', async () => {
    await assertSucceeds(setDoc(doc(db(GUEST), `${S}/activity/e1`),
      { type: 'guestPicked', actorPid: 'p2', at: 1 }));
    await assertSucceeds(setDoc(doc(db(OWNER), `${S}/activity/e2`),
      { type: 'ticketAdded', at: 2 }));
    await assertFails(updateDoc(doc(db(GUEST), `${S}/activity/e1`),
      { type: 'x' }));
    await assertFails(deleteDoc(doc(db(OWNER), `${S}/activity/e1`)));
  });

  it('evento sin forma mínima: denegado', () =>
    assertFails(setDoc(doc(db(GUEST), `${S}/activity/e9`), { foo: 1 })));
});

// ─── users ───────────────────────────────────────────────────────────────
describe('users', () => {
  it('cada uno lo suyo y nada de nadie más', async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), 'users/owner-uid')));
    await assertSucceeds(setDoc(
      doc(db(OWNER), 'users/owner-uid/frequentPeople/f1'), { name: 'Alba' }));
    await assertFails(getDoc(doc(db(GUEST), 'users/owner-uid')));
    await assertFails(setDoc(doc(db(GUEST), 'users/owner-uid'), { a: 1 }));
    await assertFails(getDoc(doc(db(null), 'users/owner-uid')));
  });

  it('perfiles privados requieren una cuenta verificada', async () => {
    await assertFails(setDoc(doc(db(GUEST), `users/${GUEST}`),
      { displayName: 'Invitado' }));
    await assertFails(setDoc(doc(db(UNVERIFIED), `users/${UNVERIFIED}`),
      { displayName: 'Pendiente' }));
    await assertSucceeds(setDoc(doc(db(STRANGER), `users/${STRANGER}`),
      { displayName: 'Verificada' }));
  });
});

// ─── Espacios compartidos (P4) ──────────────────────────────────────────
describe('spaces', () => {
  // El owner de los espacios sembrados necesita su perfil público (P3 lo
  // siembra igual en sus suites): canUseSocial lo exige.
  beforeEach(seedSocialProfiles);

  const spaceDoc = () => ({
    name: 'Piso',
    ownerUid: FOURTH,
    status: 'active',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
  });

  const createSpace = (f, uid, spaceId, overrides = {}) => {
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/${spaceId}`),
      { ...spaceDoc(), ownerUid: uid, ...overrides });
    batch.set(doc(f, `spaces/${spaceId}/members/${uid}`), {
      uid, joinedAt: serverTimestamp(),
    });
    return batch.commit();
  };

  it('cuenta completa crea espacio + membresía owner en batch', () =>
    assertSucceeds(createSpace(db(FOURTH), FOURTH, 'nuevo')));

  it('crea una relación canónica con invitación en el mismo batch', async () => {
    const relationId = `relationship_${FOURTH}~${THIRD}`;
    const f = db(FOURTH);
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/${relationId}`), {
      name: 'Relación', ownerUid: FOURTH, kind: 'relationship',
      relationshipUids: [FOURTH, THIRD], status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    batch.set(doc(f, `spaces/${relationId}/members/${FOURTH}`), {
      uid: FOURTH, joinedAt: serverTimestamp(),
    });
    batch.set(doc(f, `spaceInvites/${relationId}_${THIRD}`), {
      spaceId: relationId, spaceName: 'Relación', fromUid: FOURTH,
      toUid: THIRD, status: 'pending', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('deniega relación con id no canónico o invitación a un tercer UID',
      async () => {
    await assertFails(createSpace(db(FOURTH), FOURTH, 'relacion-falsa', {
      kind: 'relationship', relationshipUids: [FOURTH, THIRD],
      schemaVersion: 2,
    }));

    const relationId = `relationship_${FOURTH}~${THIRD}`;
    const f = db(FOURTH);
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/${relationId}`), {
      name: 'Relación', ownerUid: FOURTH, kind: 'relationship',
      relationshipUids: [FOURTH, THIRD], status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    batch.set(doc(f, `spaces/${relationId}/members/${FOURTH}`), {
      uid: FOURTH, joinedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertFails(setDoc(
      doc(f, `spaceInvites/${relationId}_${SOCIAL_OUTSIDER}`), {
        spaceId: relationId, spaceName: 'Relación', fromUid: FOURTH,
        toUid: SOCIAL_OUTSIDER, status: 'pending',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      }));
  });

  it('espacio sin membresía owner en el batch: denegado', () =>
    assertFails(setDoc(doc(db(FOURTH), 'spaces/suelto'), spaceDoc())));

  it('anónimos, no verificados y cuentas sin perfil no crean espacios',
      async () => {
    await assertFails(createSpace(db(GUEST), GUEST, 'gx'));
    await assertFails(createSpace(db(UNVERIFIED), UNVERIFIED, 'ux'));
    await assertFails(
      createSpace(db('noprofile-uid'), 'noprofile-uid', 'nx'));
  });

  it('lee un espacio SOLO quien es miembro', async () => {
    await assertSucceeds(getDoc(doc(db(SOCIAL_OUTSIDER), 'spaces/sp1')));
    await assertSucceeds(getDoc(doc(db(STRANGER), 'spaces/sp1')));
    await assertFails(getDoc(doc(db(FOURTH), 'spaces/sp1')));
  });

  it('collection group: cada uno lista SOLO sus membresías', async () => {
    await assertSucceeds(getDocs(query(
      collectionGroup(db(STRANGER), 'members'),
      where('uid', '==', STRANGER))));
    await assertFails(getDocs(query(
      collectionGroup(db(FOURTH), 'members'),
      where('uid', '==', STRANGER))));
  });

  it('el owner edita nombre y archiva/reactiva; un miembro no', async () => {
    const owner = db(SOCIAL_OUTSIDER);
    await assertSucceeds(updateDoc(doc(owner, 'spaces/sp1'),
      { name: 'Viaje 2026', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(owner, 'spaces/sp1'),
      { status: 'archived', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(owner, 'spaces/sp1'),
      { status: 'active', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(STRANGER), 'spaces/sp1'),
      { name: 'Golpe', updatedAt: serverTimestamp() }));
  });

  it('transferencia atómica (un doc: ownerUid) a un miembro activo', async () => {
    await assertSucceeds(updateDoc(doc(db(SOCIAL_OUTSIDER), 'spaces/sp1'),
      { ownerUid: STRANGER, updatedAt: serverTimestamp() }));
    // El anterior owner ya no puede administrar; el nuevo, sí.
    await assertFails(updateDoc(doc(db(SOCIAL_OUTSIDER), 'spaces/sp1'),
      { name: 'Golpe', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db(STRANGER), 'spaces/sp1'),
      { name: 'Nuevo rumbo', updatedAt: serverTimestamp() }));
  });

  it('transferencia a un NO-miembro o por un no-owner: denegada', async () => {
    await assertFails(updateDoc(doc(db(SOCIAL_OUTSIDER), 'spaces/sp1'),
      { ownerUid: FOURTH, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(STRANGER), 'spaces/sp1'),
      { ownerUid: STRANGER, updatedAt: serverTimestamp() }));
  });

  it('no hay borrado de espacios (archivar es la única baja)', () =>
    assertFails(deleteDoc(doc(db(SOCIAL_OUTSIDER), 'spaces/sp1'))));

  it('el owner invita a una cuenta con perfil que no es miembro', () =>
    assertSucceeds(setDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${FOURTH}`), {
        spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
        toUid: FOURTH, status: 'pending', createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      })));

  it('invitaciones inválidas: id no canónico, miembro, no-owner, archivado',
      async () => {
    const base = {
      spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
      toUid: FOURTH, status: 'pending', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceInvites/otro-id'), base));
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${STRANGER}`),
      { ...base, toUid: STRANGER }));
    await assertFails(setDoc(
      doc(db(STRANGER), `spaceInvites/sp1_${FOURTH}`),
      { ...base, fromUid: STRANGER }));
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp2_${FOURTH}`),
      { ...base, spaceId: 'sp2', spaceName: 'Antiguo' }));
  });

  it('aceptar: el receptor resuelve la invitación Y se une en el batch',
      async () => {
    const f = db(THIRD);
    const batch = writeBatch(f);
    batch.update(doc(f, `spaceInvites/sp1_${THIRD}`),
      { status: 'accepted', updatedAt: serverTimestamp() });
    batch.set(doc(f, `spaces/sp1/members/${THIRD}`), {
      uid: THIRD, joinedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('unirse sin resolver la invitación (o sin invitación): denegado',
      async () => {
    await assertFails(setDoc(doc(db(THIRD), `spaces/sp1/members/${THIRD}`), {
      uid: THIRD, joinedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db(FOURTH), `spaces/sp1/members/${FOURTH}`), {
      uid: FOURTH, joinedAt: serverTimestamp(),
    }));
  });

  it('nadie acepta ni rechaza una invitación ajena', async () => {
    await assertFails(updateDoc(doc(db(STRANGER), `spaceInvites/sp1_${THIRD}`),
      { status: 'rejected', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${THIRD}`),
      { status: 'accepted', updatedAt: serverTimestamp() }));
  });

  it('rechazo del receptor, cancelación del owner y reenvío', async () => {
    await assertSucceeds(updateDoc(doc(db(THIRD), `spaceInvites/sp1_${THIRD}`),
      { status: 'rejected', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${THIRD}`),
      { status: 'pending', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${THIRD}`),
      { status: 'cancelled', updatedAt: serverTimestamp() }));
    // Cancelada: el receptor ya no puede aceptarla (ni unirse).
    const f = db(THIRD);
    const batch = writeBatch(f);
    batch.update(doc(f, `spaceInvites/sp1_${THIRD}`),
      { status: 'accepted', updatedAt: serverTimestamp() });
    batch.set(doc(f, `spaces/sp1/members/${THIRD}`), {
      uid: THIRD, joinedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('salir (miembro), expulsión (owner) y límites', async () => {
    // El miembro sale por sí mismo.
    await assertSucceeds(
      deleteDoc(doc(db(STRANGER), `spaces/sp1/members/${STRANGER}`)));
    // El owner NO puede borrarse a sí mismo (transferir antes).
    await assertFails(deleteDoc(doc(
      db(SOCIAL_OUTSIDER), `spaces/sp1/members/${SOCIAL_OUTSIDER}`)));
    // Un tercero no expulsa a nadie.
    await assertFails(
      deleteDoc(doc(db(FOURTH), `spaces/sp1/members/${STRANGER}`)));
  });

  it('el owner expulsa a un miembro', () =>
    assertSucceeds(deleteDoc(
      doc(db(SOCIAL_OUTSIDER), `spaces/sp1/members/${STRANGER}`))));

  it('tickets vinculados: los miembros del espacio leen el resumen', async () => {
    await assertSucceeds(getDocs(query(
      collectionGroup(db(STRANGER), 'tickets'),
      where('spaceId', '==', 'sp1'))));
    await assertFails(getDocs(query(
      collectionGroup(db(FOURTH), 'tickets'),
      where('spaceId', '==', 'sp1'))));
  });

  it('vincular ticket: solo a un espacio del que el dueño es miembro',
      async () => {
    await assertSucceeds(updateDoc(
      doc(db(OWNER), `${S}/accounts/a1/tickets/t1`), { spaceId: 'sp1' }));
    // Desvincular siempre es seguro.
    await assertSucceeds(updateDoc(
      doc(db(OWNER), `${S}/accounts/a1/tickets/t1`), { spaceId: '' }));
    // Espacio del que NO es miembro: denegado.
    await assertSucceeds(createSpace(db(FOURTH), FOURTH, 'ajeno'));
    await assertFails(updateDoc(
      doc(db(OWNER), `${S}/accounts/a1/tickets/t1`), { spaceId: 'ajeno' }));
  });
});

// ─── Relaciones económicas (P5): solo participantes, solo lectura ──────
describe('economic relations', () => {
  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'economicEntries/e1'), {
        memberUids: [OWNER, STRANGER].sort(),
        debtorUid: STRANGER, creditorUid: OWNER,
        amount: 1000, currency: 'EUR', sessionId: 's1',
        accountId: 'a1', ticketId: 't1', ticketName: 'Cena',
        schemaVersion: 1,
      });
      await setDoc(doc(f, 'economicPayments/p1'), {
        memberUids: [OWNER, STRANGER].sort(), pairId: 'pair',
        payerUid: STRANGER, receiverUid: OWNER,
        amount: 400, currency: 'EUR', status: 'confirmed',
        source: 'user', schemaVersion: 1,
      });
    });
  });

  it('cada participante lee su deuda y pagos; terceros no', async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), 'economicEntries/e1')));
    await assertSucceeds(getDoc(doc(db(STRANGER), 'economicPayments/p1')));
    await assertFails(getDoc(doc(db(SOCIAL_OUTSIDER), 'economicEntries/e1')));
    await assertFails(getDoc(doc(db(GUEST), 'economicEntries/e1')));
    await assertFails(getDoc(doc(db(UNVERIFIED), 'economicPayments/p1')));
  });

  it('las queries están acotadas por arrayContains al UID propio', async () => {
    await assertSucceeds(getDocs(query(
      collection(db(OWNER), 'economicEntries'),
      where('memberUids', 'array-contains', OWNER),
    )));
    await assertFails(getDocs(collection(db(OWNER), 'economicEntries')));
    await assertFails(getDocs(query(
      collection(db(OWNER), 'economicEntries'),
      where('memberUids', 'array-contains', STRANGER),
    )));
  });

  it('ningún cliente escribe saldos ni pagos, aunque sea participante', async () => {
    await assertFails(setDoc(doc(db(OWNER), 'economicEntries/hack'), {
      memberUids: [OWNER, STRANGER].sort(), amount: 1,
    }));
    await assertFails(updateDoc(doc(db(OWNER), 'economicEntries/e1'), {
      amount: 1,
    }));
    await assertFails(setDoc(doc(db(STRANGER), 'economicPayments/hack'), {
      memberUids: [OWNER, STRANGER].sort(), amount: 1,
    }));
    await assertFails(deleteDoc(doc(db(OWNER), 'economicPayments/p1')));
  });
});

// ─── Actividad (P6): proyección de auditoría ────────────────────────────
describe('activityEvents', () => {
  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      // Evento con audiencia congelada: STRANGER y SOCIAL_OUTSIDER.
      await setDoc(doc(f, 'activityEvents/ev1'), {
        type: 'space_created', actorUid: SOCIAL_OUTSIDER,
        memberUids: [SOCIAL_OUTSIDER, STRANGER], spaceId: 'sp1',
        summary: { spaceName: 'Viaje' }, at: serverTimestamp(),
        schemaVersion: 1,
      });
      await setDoc(doc(f, 'activityEvents/ev2'), {
        type: 'payment_confirmed', actorUid: STRANGER,
        memberUids: [STRANGER, THIRD], paymentId: 'pay1',
        summary: { amount: 500, currency: 'EUR' }, at: serverTimestamp(),
        schemaVersion: 1,
      });
    });
  });

  it('lee un evento SOLO quien está en su audiencia congelada', async () => {
    await assertSucceeds(getDoc(doc(db(STRANGER), 'activityEvents/ev1')));
    await assertSucceeds(getDoc(doc(db(THIRD), 'activityEvents/ev2')));
    // THIRD es miembro actual de nada en ev1: fuera de audiencia, fuera.
    await assertFails(getDoc(doc(db(THIRD), 'activityEvents/ev1')));
    await assertFails(getDoc(doc(db(FOURTH), 'activityEvents/ev2')));
  });

  it('la query global (array-contains propio + orden) es demostrable', () =>
    assertSucceeds(getDocs(query(
      collection(db(STRANGER), 'activityEvents'),
      where('memberUids', 'array-contains', STRANGER)))));

  it('anónimos y no verificados no leen actividad', async () => {
    await assertFails(getDoc(doc(db(GUEST), 'activityEvents/ev1')));
    await assertFails(getDoc(doc(db(UNVERIFIED), 'activityEvents/ev1')));
  });

  it('ningún cliente escribe eventos (ni fraudulentos a nombre de otro)',
      async () => {
    await assertFails(setDoc(doc(db(STRANGER), 'activityEvents/falso'), {
      type: 'payment_confirmed', actorUid: THIRD,
      memberUids: [STRANGER, THIRD], summary: {},
      at: serverTimestamp(), schemaVersion: 1,
    }));
    await assertFails(updateDoc(doc(db(STRANGER), 'activityEvents/ev1'),
      { actorUid: STRANGER }));
    await assertFails(deleteDoc(doc(db(STRANGER), 'activityEvents/ev1')));
  });

  it('P6: el owner marca removedBy antes de expulsar; nadie más', async () => {
    // El owner del espacio sembrado (SOCIAL_OUTSIDER) marca a STRANGER.
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaces/sp1/members/${STRANGER}`),
      { removedBy: SOCIAL_OUTSIDER }));
    // No puede marcarse a sí mismo (el owner no se expulsa).
    await assertFails(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaces/sp1/members/${SOCIAL_OUTSIDER}`),
      { removedBy: SOCIAL_OUTSIDER }));
    // Un miembro no marca a otro, ni con uid falso.
    await assertFails(updateDoc(
      doc(db(STRANGER), `spaces/sp1/members/${OWNER}`),
      { removedBy: STRANGER }));
    await assertFails(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaces/sp1/members/${STRANGER}`),
      { removedBy: STRANGER }));
  });
});

// Nota: assert está importado para fallos explícitos en helpers futuros.
void assert;
