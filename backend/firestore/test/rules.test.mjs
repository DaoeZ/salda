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
  limit,
  orderBy,
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

  // REGRESIÓN: la app NO escribe a ciegas. Invitar y crear una relación
  // empiezan leyendo dentro de una transacción el documento que van a
  // crear (para ser idempotentes), y ese documento todavía NO existe.
  // Si `read` no contempla `resource == null`, la transacción muere con
  // permission-denied antes de escribir nada.
  it('grupo: invitar lee la invitación inexistente y la crea (como la app)',
      async () => {
    const f = db(SOCIAL_OUTSIDER); // owner de sp1
    const inviteId = `sp1_${FOURTH}`;
    await assertSucceeds(runTransaction(f, async (tx) => {
      const existing = await tx.get(doc(f, `spaceInvites/${inviteId}`));
      assert.equal(existing.exists(), false);
      tx.set(doc(f, `spaceInvites/${inviteId}`), {
        spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
        toUid: FOURTH, status: 'pending', createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }));
  });

  it('relación: se lee el espacio inexistente y se crea entero (como la app)',
      async () => {
    const relationId = `relationship_${FOURTH}~${THIRD}`;
    const f = db(FOURTH);
    await assertSucceeds(runTransaction(f, async (tx) => {
      const existing = await tx.get(doc(f, `spaces/${relationId}`));
      assert.equal(existing.exists(), false);
      tx.set(doc(f, `spaces/${relationId}`), {
        name: 'Relación', ownerUid: FOURTH, kind: 'relationship',
        relationshipUids: [FOURTH, THIRD], status: 'active',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 2,
      });
      tx.set(doc(f, `spaces/${relationId}/members/${FOURTH}`), {
        uid: FOURTH, joinedAt: serverTimestamp(),
      });
      tx.set(doc(f, `spaceInvites/${relationId}_${THIRD}`), {
        spaceId: relationId, spaceName: 'Relación', fromUid: FOURTH,
        toUid: THIRD, status: 'pending', createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }));
  });

  // ── Participantes manuales (ADR-033) ──────────────────────────────────
  const manualDoc = (manualId, overrides = {}) => ({
    manualId,
    displayName: 'Lucía',
    linkedUid: null,
    createdByUid: SOCIAL_OUTSIDER,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  it('MANUAL: el owner crea una persona sin cuenta y cualquier miembro la ve',
      async () => {
    await assertSucceeds(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaces/sp1/manualParticipants/mp1'),
      manualDoc('mp1')));
    await assertSucceeds(
      getDoc(doc(db(STRANGER), 'spaces/sp1/manualParticipants/mp1')));
  });

  it('MANUAL: solo el owner la crea; ni un miembro ni un extraño', async () => {
    await assertFails(setDoc(
      doc(db(STRANGER), 'spaces/sp1/manualParticipants/mp2'),
      manualDoc('mp2', { createdByUid: STRANGER })));
    await assertFails(setDoc(
      doc(db(FOURTH), 'spaces/sp1/manualParticipants/mp3'),
      manualDoc('mp3', { createdByUid: FOURTH })));
  });

  it('MANUAL: forma inválida denegada (id, nombre, vínculo o autoría)',
      async () => {
    const f = db(SOCIAL_OUTSIDER);
    // manualId incompatible con el actor `manual:{id}`.
    await assertFails(setDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp:x'), manualDoc('mp:x')));
    // El campo debe coincidir con el id del documento.
    await assertFails(setDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp4'), manualDoc('otro')));
    await assertFails(setDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp5'),
      manualDoc('mp5', { displayName: '' })));
    // La vinculación con una cuenta es fase futura: hoy siempre null.
    await assertFails(setDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp6'),
      manualDoc('mp6', { linkedUid: FOURTH })));
    // No se puede atribuir la creación a otro.
    await assertFails(setDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp7'),
      manualDoc('mp7', { createdByUid: STRANGER })));
  });

  it('MANUAL: se renombra, pero identidad y vínculo son inmutables',
      async () => {
    const f = db(SOCIAL_OUTSIDER);
    await setDoc(doc(f, 'spaces/sp1/manualParticipants/mp8'), manualDoc('mp8'));

    await assertSucceeds(updateDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp8'),
      { displayName: 'Lucía G.', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp8'),
      { manualId: 'otro', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(
      doc(f, 'spaces/sp1/manualParticipants/mp8'),
      { linkedUid: FOURTH, updatedAt: serverTimestamp() }));
    // Un miembro cualquiera no la renombra.
    await assertFails(updateDoc(
      doc(db(STRANGER), 'spaces/sp1/manualParticipants/mp8'),
      { displayName: 'Hack', updatedAt: serverTimestamp() }));
  });

  it('MANUAL: la retira el owner; un miembro no', async () => {
    const f = db(SOCIAL_OUTSIDER);
    await setDoc(doc(f, 'spaces/sp1/manualParticipants/mp9'), manualDoc('mp9'));
    await assertFails(
      deleteDoc(doc(db(STRANGER), 'spaces/sp1/manualParticipants/mp9')));
    await assertSucceeds(
      deleteDoc(doc(f, 'spaces/sp1/manualParticipants/mp9')));
  });

  it('MANUAL: un extraño no lista las personas sin cuenta del espacio', () =>
    assertFails(getDocs(collection(db(FOURTH),
      'spaces/sp1/manualParticipants'))));

  it('invitar comprueba antes si el destino ya es miembro (get ajeno)', () =>
    assertSucceeds(
      getDoc(doc(db(SOCIAL_OUTSIDER), `spaces/sp1/members/${FOURTH}`))));

  it('leer un espacio o invitación ajenos inexistentes SIGUE denegado',
      async () => {
    // El hueco de lectura no puede convertirse en un oráculo de existencia
    // para terceros: FOURTH no participa en esta pareja ni en sp2.
    await assertFails(getDoc(
      doc(db(FOURTH), `spaces/relationship_${THIRD}~${SOCIAL_OUTSIDER}`)));
    await assertFails(getDoc(doc(db(FOURTH), `spaceInvites/sp2_${THIRD}`)));
  });

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

// ─── Chat contextual (P7): membresía + frontera temporal ────────────────
describe('space chat', () => {
  const joinedAt = new Date('2026-07-01T10:00:00.000Z');
  const thirdJoinedAt = new Date('2026-07-03T10:00:00.000Z');
  const visibleAt = new Date('2026-07-02T10:00:00.000Z');
  const afterThirdAt = new Date('2026-07-04T10:00:00.000Z');

  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      for (const uid of [SOCIAL_OUTSIDER, STRANGER, OWNER]) {
        await setDoc(doc(f, `spaces/sp1/members/${uid}`), {
          uid,
          joinedAt,
        });
      }
      await setDoc(doc(f, `spaces/sp1/members/${THIRD}`), {
        uid: THIRD,
        joinedAt: thirdJoinedAt,
      });
      await setDoc(doc(f, 'spaces/sp1/messages/before'), {
        authorUid: SOCIAL_OUTSIDER,
        text: 'Conversación anterior',
        createdAt: new Date('2026-06-30T10:00:00.000Z'),
        schemaVersion: 1,
      });
      await setDoc(doc(f, 'spaces/sp1/messages/visible'), {
        authorUid: SOCIAL_OUTSIDER,
        text: 'Mensaje visible',
        createdAt: visibleAt,
        schemaVersion: 1,
      });
      await setDoc(doc(f, 'spaces/sp1/messages/after-third'), {
        authorUid: STRANGER,
        text: 'Mensaje para todos los miembros actuales',
        createdAt: afterThirdAt,
        schemaVersion: 1,
      });
      await setDoc(doc(f, 'spaces/sp2/messages/archived'), {
        authorUid: SOCIAL_OUTSIDER,
        text: 'Contexto archivado',
        createdAt: visibleAt,
        schemaVersion: 1,
      });
    });
  });

  const chatQuery = (f, spaceId, cutoff) => query(
    collection(f, `spaces/${spaceId}/messages`),
    where('createdAt', '>=', cutoff),
    orderBy('createdAt', 'desc'),
    limit(40),
  );

  const validMessage = (overrides = {}) => ({
    authorUid: STRANGER,
    text: 'Hola, grupo',
    createdAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  it('miembro actual consulta solo desde su fecha de incorporación', async () => {
    const snapshot = await assertSucceeds(
      getDocs(chatQuery(db(STRANGER), 'sp1', joinedAt)),
    );
    assert.deepEqual(
      snapshot.docs.map((document) => document.id),
      ['after-third', 'visible'],
    );
    await assertFails(getDoc(doc(db(STRANGER), 'spaces/sp1/messages/before')));
  });

  it('miembro nuevo no hereda historial y la consulta sin cota se deniega',
      async () => {
    await assertFails(
      getDoc(doc(db(THIRD), 'spaces/sp1/messages/visible')),
    );
    const snapshot = await assertSucceeds(
      getDocs(chatQuery(db(THIRD), 'sp1', thirdJoinedAt)),
    );
    assert.deepEqual(
      snapshot.docs.map((document) => document.id),
      ['after-third'],
    );
    await assertFails(getDocs(query(
      collection(db(THIRD), 'spaces/sp1/messages'),
      orderBy('createdAt', 'desc'),
      limit(40),
    )));
  });

  it('no miembros, invitados anónimos y cuentas no verificadas no leen',
      async () => {
    await assertFails(
      getDoc(doc(db(FOURTH), 'spaces/sp1/messages/visible')),
    );
    await assertFails(
      getDoc(doc(db(GUEST), 'spaces/sp1/messages/visible')),
    );
    await assertFails(
      getDoc(doc(db(UNVERIFIED), 'spaces/sp1/messages/visible')),
    );
  });

  it('miembro activo envía con identidad propia y server timestamp',
      async () => {
    await assertSucceeds(setDoc(
      doc(db(STRANGER), 'spaces/sp1/messages/new'),
      validMessage(),
    ));
    await assertFails(setDoc(
      doc(db(STRANGER), 'spaces/sp2/messages/new'),
      validMessage(),
    ));
  });

  it('deniega suplantación, forma inválida y campos adicionales', async () => {
    const target = (id) => doc(db(STRANGER), `spaces/sp1/messages/${id}`);
    await assertFails(setDoc(
      target('spoof'),
      validMessage({ authorUid: OWNER }),
    ));
    await assertFails(setDoc(target('empty'), validMessage({ text: '' })));
    await assertFails(setDoc(
      target('long'),
      validMessage({ text: 'x'.repeat(2001) }),
    ));
    await assertFails(setDoc(
      target('schema'),
      validMessage({ schemaVersion: 2 }),
    ));
    await assertFails(setDoc(
      target('extra'),
      validMessage({ moderation: true }),
    ));
  });

  it('mensajes inmutables; solo el autor borra en un espacio activo',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'spaces/sp1/messages/third-before'), {
        authorUid: THIRD,
        text: 'Mensaje propio de una membresía anterior',
        createdAt: visibleAt,
        schemaVersion: 1,
      });
    });
    await assertFails(updateDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaces/sp1/messages/visible'),
      { text: 'Editado' },
    ));
    await assertFails(deleteDoc(
      doc(db(STRANGER), 'spaces/sp1/messages/visible'),
    ));
    await assertFails(deleteDoc(
      doc(db(THIRD), 'spaces/sp1/messages/third-before'),
    ));
    await assertSucceeds(deleteDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaces/sp1/messages/visible'),
    ));
    await assertFails(deleteDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaces/sp2/messages/archived'),
    ));
  });

  it('al salir se pierde inmediatamente todo acceso al chat', async () => {
    const memberDb = db(STRANGER);
    await assertSucceeds(
      deleteDoc(doc(memberDb, `spaces/sp1/members/${STRANGER}`)),
    );
    await assertFails(
      getDoc(doc(memberDb, 'spaces/sp1/messages/after-third')),
    );
    await assertFails(setDoc(
      doc(memberDb, 'spaces/sp1/messages/after-leave'),
      validMessage(),
    ));
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

// ─── Modo invitado (GUEST, ADR-034) ─────────────────────────────────────
describe('guest', () => {
  // GUEST = Auth anónimo CON identidad de invitado. La identidad persiste
  // en el dispositivo (la sesión anónima de Firebase sobrevive a reinicios).
  const identity = (uid, overrides = {}) => ({
    uid,
    displayName: 'Invitada',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `guestIdentities/${GUEST}`), {
        uid: GUEST, displayName: 'Alba invitada',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
      // El invitado ya es miembro de sp1 (su alta se prueba aparte).
      await setDoc(doc(f, `spaces/sp1/members/${GUEST}`), {
        uid: GUEST, kind: 'guest', displayName: 'Alba invitada',
        joinedAt: serverTimestamp(),
      });
    });
  });

  it('crea y mantiene su identidad; nadie más puede escribirla', async () => {
    await assertSucceeds(setDoc(
      doc(db(OTHER), `guestIdentities/${OTHER}`), identity(OTHER)));
    // Renombrarse: el nombre visible es suyo.
    await assertSucceeds(updateDoc(
      doc(db(GUEST), `guestIdentities/${GUEST}`),
      { displayName: 'Alba G.', updatedAt: serverTimestamp() }));
    // Suplantación y escritura ajena: denegadas.
    await assertFails(setDoc(
      doc(db(OTHER), `guestIdentities/${GUEST}`), identity(GUEST)));
    await assertFails(updateDoc(
      doc(db(STRANGER), `guestIdentities/${GUEST}`),
      { displayName: 'Hack', updatedAt: serverTimestamp() }));
    // Forma inválida (nombre vacío o campo de más).
    await assertFails(setDoc(
      doc(db(OTHER), `guestIdentities/${OTHER}`),
      identity(OTHER, { displayName: '' })));
    await assertFails(setDoc(
      doc(db(OTHER), `guestIdentities/${OTHER}`),
      identity(OTHER, { username: 'alba' })));
  });

  it('la identidad NO es pública: se lee por UID pero jamás es buscable',
      async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), `guestIdentities/${GUEST}`)));
    await assertFails(getDocs(collection(db(OWNER), 'guestIdentities')));
  });

  it('participa: lee su contexto, sus miembros y sus balances', async () => {
    await assertSucceeds(getDoc(doc(db(GUEST), 'spaces/sp1')));
    await assertSucceeds(
      getDocs(collection(db(GUEST), 'spaces/sp1/members')));
    await assertSucceeds(getDocs(query(
      collection(db(GUEST), 'economicEntries'),
      where('memberUids', 'array-contains', GUEST))));
  });

  it('NO crea contextos, ni invita, ni administra, ni tiene perfil público',
      async () => {
    // Crear un espacio (aunque sea con su propia membresía en el batch).
    const f = db(GUEST);
    const batch = writeBatch(f);
    batch.set(doc(f, 'spaces/guest-space'), {
      name: 'Mío', ownerUid: GUEST, status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    batch.set(doc(f, `spaces/guest-space/members/${GUEST}`), {
      uid: GUEST, joinedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());

    // Invitar a alguien a un contexto del que es miembro.
    await assertFails(setDoc(doc(f, `spaceInvites/sp1_${FOURTH}`), {
      spaceId: 'sp1', spaceName: 'Viaje', fromUid: GUEST, toUid: FOURTH,
      status: 'pending', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
    // Administrar: renombrar, archivar, transferir o expulsar.
    await assertFails(updateDoc(doc(f, 'spaces/sp1'),
      { name: 'Renombrado', updatedAt: serverTimestamp() }));
    await assertFails(
      deleteDoc(doc(f, `spaces/sp1/members/${STRANGER}`)));
    // Perfil público y amistades: fuera de su alcance.
    await assertFails(setDoc(doc(f, `profiles/${GUEST}`), {
      displayName: 'Alba', displayNameLower: 'alba', username: 'albaguest',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    }));
    await assertFails(setDoc(
      doc(f, `friendships/${friendshipId(GUEST, STRANGER)}`),
      friendshipData(GUEST, STRANGER)));
  });

  it('el anfitrión puede invitar a un invitado (sin perfil público)',
      async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `guestIdentities/${OTHER}`), {
        uid: OTHER, displayName: 'Lucía invitada',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      }));
    await assertSucceeds(setDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceInvites/sp1_${OTHER}`), {
        spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
        toUid: OTHER, status: 'pending', createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }));
    // Un UID sin ninguna identidad (ni perfil ni invitado) sigue denegado.
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceInvites/sp1_fantasma-uid'), {
        spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
        toUid: 'fantasma-uid', status: 'pending',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      }));
  });

  it('se une aceptando su invitación, con su nombre como snapshot',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `guestIdentities/${OTHER}`), {
        uid: OTHER, displayName: 'Lucía invitada',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
      await setDoc(doc(f, `spaceInvites/sp1_${OTHER}`), {
        spaceId: 'sp1', spaceName: 'Viaje', fromUid: SOCIAL_OUTSIDER,
        toUid: OTHER, status: 'pending', createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    });

    const f = db(OTHER);
    const batch = writeBatch(f);
    batch.update(doc(f, `spaceInvites/sp1_${OTHER}`),
      { status: 'accepted', updatedAt: serverTimestamp() });
    batch.set(doc(f, `spaces/sp1/members/${OTHER}`), {
      uid: OTHER, kind: 'guest', displayName: 'Lucía invitada',
      joinedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('gastos: solo si el anfitrión lo permite en ese contexto', async () => {
    const session = {
      ownerUid: GUEST, kind: 'single', name: 'Cena', status: 'open',
      splitModeDefault: 'equal', shareCode: 'GUEST-CODE-16CHARS',
      currency: 'EUR', computeVersion: 0,
      contextModelVersion: 1, spaceId: 'sp1',
    };
    // Por defecto (bandera ausente) el invitado NO origina gasto.
    await assertFails(setDoc(doc(db(GUEST), 'sessions/guest-1'), session));

    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), 'spaces/sp1'), { guestsCanCreateExpenses: true }));
    await assertSucceeds(setDoc(doc(db(GUEST), 'sessions/guest-2'), session));

    // Un miembro con cuenta nunca depende de esa bandera.
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), 'spaces/sp1'), { guestsCanCreateExpenses: false }));
    await assertSucceeds(setDoc(doc(db(OWNER), 'sessions/host-1'),
      { ...session, ownerUid: OWNER, shareCode: 'HOST-CODE-16CHARSX' }));
  });

  it('la política de invitados solo la fija el owner del contexto',
      async () => {
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaces/sp1'),
      { guestsCanCreateExpenses: true, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(GUEST), 'spaces/sp1'),
      { guestsCanCreateExpenses: true, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db(STRANGER), 'spaces/sp1'),
      { guestsCanCreateExpenses: true, updatedAt: serverTimestamp() }));
  });

  it('un anónimo SIN identidad de invitado no participa', async () => {
    // OTHER es anónimo pero aún no ha elegido nombre: no es guest.
    await assertFails(getDoc(doc(db(OTHER), 'spaces/sp1')));
  });
});

// ─── Enlaces de grupo (Sprint 4, ADR-035) ──────────────────────────────
describe('enlaces de grupo', () => {
  // sp1 (grupo activo) lo posee SOCIAL_OUTSIDER; STRANGER y OWNER son
  // miembros; FOURTH está fuera; GUEST es un anónimo con identidad.
  const TOKEN = 'AAAAAAAAAAAAAAAAAAAAAA'; // 22 chars, como un ShareCode real
  const OTHER_TOKEN = 'BBBBBBBBBBBBBBBBBBBBBB';
  const DEAD_TOKEN = 'CCCCCCCCCCCCCCCCCCCCCC';

  const linkDoc = (overrides = {}) => ({
    spaceId: 'sp1',
    spaceName: 'Viaje',
    createdByUid: SOCIAL_OUTSIDER,
    status: 'active',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  /** Canje completo: prueba de conocimiento + membresía en UN batch. */
  const redeem = (f, uid, token, spaceId = 'sp1', memberExtra = {}) => {
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/${spaceId}/joinGrants/${uid}`), {
      uid, token, createdAt: serverTimestamp(),
    });
    batch.set(doc(f, `spaces/${spaceId}/members/${uid}`), {
      uid, joinedAt: serverTimestamp(), ...memberExtra,
    });
    return batch.commit();
  };

  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `spaceLinks/${TOKEN}`), linkDoc());
      await setDoc(doc(f, `spaceLinks/${DEAD_TOKEN}`),
        linkDoc({ status: 'revoked' }));
      // Enlace de OTRO grupo: sirve para probar que un token no abre un
      // espacio distinto del suyo.
      await setDoc(doc(f, `spaceLinks/${OTHER_TOKEN}`),
        linkDoc({ spaceId: 'sp2', spaceName: 'Antiguo' }));
      await setDoc(doc(f, `guestIdentities/${GUEST}`), {
        uid: GUEST, displayName: 'Alba invitada',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
      // Relación canónica: nunca debe admitir enlaces (pareja inmutable).
      await setDoc(doc(f, `spaces/relationship_a~b`), {
        name: 'Ana y Bruno', ownerUid: SOCIAL_OUTSIDER, status: 'active',
        kind: 'relationship', relationshipUids: ['a', 'b'],
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 2,
      });
      await setDoc(doc(f, `spaces/relationship_a~b/members/${SOCIAL_OUTSIDER}`),
        { uid: SOCIAL_OUTSIDER, joinedAt: serverTimestamp() });
    });
  });

  // ── Creación y gobierno del enlace ──────────────────────────────────
  it('solo el propietario crea el enlace de su grupo', async () => {
    await assertSucceeds(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/NUEVOAAAAAAAAAAAAAAAA'), linkDoc()));
    // Un MIEMBRO no puede abrir la puerta del grupo: incorporar gente sigue
    // siendo del propietario.
    await assertFails(setDoc(
      doc(db(STRANGER), 'spaceLinks/DEMIEMBROAAAAAAAAAAAA'),
      linkDoc({ createdByUid: STRANGER })));
    // Un extraño, menos aún.
    await assertFails(setDoc(
      doc(db(FOURTH), 'spaceLinks/DEEXTRANOAAAAAAAAAAAA'),
      linkDoc({ createdByUid: FOURTH })));
    // Falsear la autoría tampoco cuela.
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/FALSOAAAAAAAAAAAAAAAA'),
      linkDoc({ createdByUid: STRANGER })));
  });

  it('un espacio archivado o una RELACIÓN no admiten enlace', async () => {
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/ARCHIVADOAAAAAAAAAAAA'),
      linkDoc({ spaceId: 'sp2', spaceName: 'Antiguo' })));
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/RELACIONAAAAAAAAAAAAA'),
      linkDoc({ spaceId: 'relationship_a~b', spaceName: 'Ana y Bruno' })));
  });

  it('el enlace NUNCA es enumerable; solo lo lista su propietario',
      async () => {
    await assertFails(getDocs(collection(db(FOURTH), 'spaceLinks')));
    await assertFails(getDocs(query(
      collection(db(STRANGER), 'spaceLinks'),
      where('spaceId', '==', 'sp1'))));
    await assertSucceeds(getDocs(query(
      collection(db(SOCIAL_OUTSIDER), 'spaceLinks'),
      where('spaceId', '==', 'sp1'), where('status', '==', 'active'))));
  });

  it('quien recibe el enlace ve el nombre del grupo sin ser miembro',
      async () => {
    // Conocer el token de 128 bits ES la autorización (ADR-012).
    await assertSucceeds(getDoc(doc(db(FOURTH), `spaceLinks/${TOKEN}`)));
    await assertSucceeds(getDoc(doc(db(GUEST), `spaceLinks/${TOKEN}`)));
    // Pero seguir sin poder leer el espacio: el enlace solo dice su nombre.
    await assertFails(getDoc(doc(db(FOURTH), 'spaces/sp1')));
    // Sin sesión no se lee nada.
    await assertFails(getDoc(doc(db(null), `spaceLinks/${TOKEN}`)));
  });

  it('revocar y refrescar el rótulo son del propietario; el destino no muta',
      async () => {
    // Un miembro cualquiera no revoca el enlace del grupo.
    await assertFails(updateDoc(
      doc(db(STRANGER), `spaceLinks/${TOKEN}`),
      { status: 'revoked', updatedAt: serverTimestamp() }));
    // Reapuntar un enlace a otro grupo sería un secuestro: prohibido.
    await assertFails(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceLinks/${TOKEN}`),
      { spaceId: 'sp2', updatedAt: serverTimestamp() }));
    // Nada destructivo en caliente: primero se revoca y luego se limpia.
    await assertFails(deleteDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceLinks/${TOKEN}`)));
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceLinks/${TOKEN}`),
      { status: 'revoked', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceLinks/${DEAD_TOKEN}`)));
    // Renombrar el grupo puede refrescar el rótulo del enlace.
    await assertSucceeds(updateDoc(
      doc(db(SOCIAL_OUTSIDER), `spaceLinks/${OTHER_TOKEN}`),
      { spaceName: 'Antiguo renombrado', updatedAt: serverTimestamp() }));
  });

  // ── Caducidad ───────────────────────────────────────────────────────
  it('la caducidad es opcional pero nunca puede nacer en el pasado',
      async () => {
    const future = new Date(Date.now() + 86400000);
    const past = new Date(Date.now() - 60000);
    await assertSucceeds(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/CONCADUCIDADAAAAAAAAA'),
      linkDoc({ expiresAt: future })));
    // Nacer caducado enmascararía un reloj mal puesto en el cliente.
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/YACADUCADOAAAAAAAAAAA'),
      linkDoc({ expiresAt: past })));
    // Y tiene que ser una fecha, no cualquier cosa.
    await assertFails(setDoc(
      doc(db(SOCIAL_OUTSIDER), 'spaceLinks/BASURAAAAAAAAAAAAAAAA'),
      linkDoc({ expiresAt: 'mañana' })));
  });

  it('un enlace caducado no admite a nadie, aunque siga active', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Caducado pero SIN revocar: son dos cosas distintas y ambas cierran.
      await setDoc(doc(ctx.firestore(), 'spaceLinks/CADUCADOAAAAAAAAAAAAA'),
        { ...linkDoc(), expiresAt: new Date(Date.now() - 60000) });
    });
    await assertFails(redeem(db(FOURTH), FOURTH, 'CADUCADOAAAAAAAAAAAAA'));
  });

  it('la caducidad es INMUTABLE: no se alarga un enlace ya repartido',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'spaceLinks/CONFECHAAAAAAAAAAAAAA'),
        { ...linkDoc(), expiresAt: new Date(Date.now() + 3600000) });
    });
    const f = db(SOCIAL_OUTSIDER);
    // Alargarla resucitaría un enlace que ya circula: para cambiarla se rota.
    await assertFails(updateDoc(doc(f, 'spaceLinks/CONFECHAAAAAAAAAAAAAA'),
      { expiresAt: new Date(Date.now() + 999999999), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(f, 'spaceLinks/CONFECHAAAAAAAAAAAAAA'),
      { expiresAt: null, updatedAt: serverTimestamp() }));
    // Revocarlo sí, siempre.
    await assertSucceeds(updateDoc(doc(f, 'spaceLinks/CONFECHAAAAAAAAAAAAAA'),
      { status: 'revoked', updatedAt: serverTimestamp() }));
  });

  // ── Canje ───────────────────────────────────────────────────────────
  it('una CUENTA entra presentando el token en el mismo batch', async () => {
    await assertSucceeds(redeem(db(FOURTH), FOURTH, TOKEN));
  });

  it('un INVITADO entra igual, con su nombre como snapshot', async () => {
    await assertSucceeds(redeem(db(GUEST), GUEST, TOKEN, 'sp1',
      { kind: 'guest', displayName: 'Alba invitada' }));
  });

  it('sin prueba de conocimiento no hay membresía', async () => {
    // Escribir solo la membresía: ni invitación ni enlace que lo respalde.
    await assertFails(setDoc(
      doc(db(FOURTH), `spaces/sp1/members/${FOURTH}`),
      { uid: FOURTH, joinedAt: serverTimestamp() }));
  });

  it('un token inventado, revocado o de OTRO grupo no abre la puerta',
      async () => {
    await assertFails(redeem(db(FOURTH), FOURTH, 'INVENTADOAAAAAAAAAAAA'));
    await assertFails(redeem(db(FOURTH), FOURTH, DEAD_TOKEN));
    // El token de sp2 no vale para entrar en sp1.
    await assertFails(redeem(db(FOURTH), FOURTH, OTHER_TOKEN));
  });

  it('el enlace no sirve para colar a un tercero ni para suplantar',
      async () => {
    // Dar de alta a OTRA persona con mi conocimiento del enlace.
    const f = db(FOURTH);
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/sp1/joinGrants/${THIRD}`),
      { uid: THIRD, token: TOKEN, createdAt: serverTimestamp() });
    batch.set(doc(f, `spaces/sp1/members/${THIRD}`),
      { uid: THIRD, joinedAt: serverTimestamp() });
    await assertFails(batch.commit());

    // Prueba a nombre propio pero membresía ajena.
    const g = db(FOURTH);
    const batch2 = writeBatch(g);
    batch2.set(doc(g, `spaces/sp1/joinGrants/${FOURTH}`),
      { uid: FOURTH, token: TOKEN, createdAt: serverTimestamp() });
    batch2.set(doc(g, `spaces/sp1/members/${THIRD}`),
      { uid: THIRD, joinedAt: serverTimestamp() });
    await assertFails(batch2.commit());
  });

  it('la prueba de conocimiento es de SOLO ESCRITURA', async () => {
    await assertSucceeds(redeem(db(FOURTH), FOURTH, TOKEN));
    // Nadie la lee — ni el propio autor ni el propietario del grupo — para
    // que el token no se filtre a los demás miembros a través de ella.
    await assertFails(getDoc(doc(db(FOURTH), `spaces/sp1/joinGrants/${FOURTH}`)));
    await assertFails(getDoc(
      doc(db(SOCIAL_OUTSIDER), `spaces/sp1/joinGrants/${FOURTH}`)));
    await assertFails(getDocs(collection(db(STRANGER), 'spaces/sp1/joinGrants')));
  });

  it('un anónimo SIN identidad de invitado no entra por enlace', async () => {
    await assertFails(redeem(db(OTHER), OTHER, TOKEN));
  });

  it('revocar el enlace cierra la puerta aunque quede una prueba vieja',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Prueba escrita cuando el enlace aún vivía; luego se revoca.
      await setDoc(doc(ctx.firestore(), `spaces/sp1/joinGrants/${FOURTH}`),
        { uid: FOURTH, token: TOKEN, createdAt: serverTimestamp() });
      await updateDoc(doc(ctx.firestore(), `spaceLinks/${TOKEN}`),
        { status: 'revoked', updatedAt: serverTimestamp() });
    });
    // La membresía revalida el enlace en CADA canje, no solo al escribir
    // la prueba: un token repartido deja de servir en cuanto se revoca.
    await assertFails(setDoc(
      doc(db(FOURTH), `spaces/sp1/members/${FOURTH}`),
      { uid: FOURTH, joinedAt: serverTimestamp() }));
  });

  // ── Regresión: las otras dos vías de alta siguen vivas ───────────────
  it('REGRESIÓN: aceptar una invitación sigue funcionando', async () => {
    // La rama (b) de members.create pasó a llevar existsAfter() por delante
    // para que entrar por enlace no muriera leyendo una invitación ausente.
    const f = db(THIRD);
    const batch = writeBatch(f);
    batch.update(doc(f, `spaceInvites/sp1_${THIRD}`),
      { status: 'accepted', updatedAt: serverTimestamp() });
    batch.set(doc(f, `spaces/sp1/members/${THIRD}`),
      { uid: THIRD, joinedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });

  it('REGRESIÓN: fundar un espacio sigue funcionando', async () => {
    const f = db(FOURTH);
    const batch = writeBatch(f);
    batch.set(doc(f, 'spaces/recien-fundado'), {
      name: 'Piso', ownerUid: FOURTH, status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    batch.set(doc(f, `spaces/recien-fundado/members/${FOURTH}`),
      { uid: FOURTH, joinedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });

  // ── El invitado ya puede LLEGAR a su grupo (ADR-034 en la práctica) ──
  it('un invitado lista sus propias membresías por collection group',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `spaces/sp1/members/${GUEST}`), {
        uid: GUEST, kind: 'guest', displayName: 'Alba invitada',
        joinedAt: serverTimestamp(),
      });
    });
    // Sin esta query el invitado quedaba dentro del grupo pero sin ninguna
    // pantalla desde la que verlo.
    await assertSucceeds(getDocs(query(
      collectionGroup(db(GUEST), 'members'),
      where('uid', '==', GUEST))));
    // Sigue sin poder espiar las membresías de otro.
    await assertFails(getDocs(query(
      collectionGroup(db(GUEST), 'members'),
      where('uid', '==', STRANGER))));
  });

  it('un invitado ve a los participantes MANUAL con los que reparte',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `spaces/sp1/members/${GUEST}`), {
        uid: GUEST, kind: 'guest', displayName: 'Alba invitada',
        joinedAt: serverTimestamp(),
      });
      await setDoc(doc(f, 'spaces/sp1/manualParticipants/mp9'), {
        manualId: 'mp9', displayName: 'Tía Marta', linkedUid: null,
        createdByUid: SOCIAL_OUTSIDER, createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(), schemaVersion: 1,
      });
    });
    await assertSucceeds(getDoc(
      doc(db(GUEST), 'spaces/sp1/manualParticipants/mp9')));
    // Pero crearlos y editarlos sigue siendo del propietario.
    await assertFails(setDoc(
      doc(db(GUEST), 'spaces/sp1/manualParticipants/mp10'), {
        manualId: 'mp10', displayName: 'Otro', linkedUid: null,
        createdByUid: GUEST, createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(), schemaVersion: 1,
      }));
  });
});

// ─── Enlaces de TICKET (Sprint 5, ADR-036) ─────────────────────────────
describe('enlaces de ticket', () => {
  // La sesión s1 la posee OWNER. p1=Edgar (owner), p2/p3 reclamados por
  // GUEST/OTHER (cuenta e invitado), p4 sin reclamar. Añadimos manuales.
  const T = 'AAAAAAAAAAAAAAAAAAAAAA'; // token del ticket t1
  const T_OTRO = 'BBBBBBBBBBBBBBBBBBBBBB'; // token de OTRO ticket (t2)
  const T_MUERTO = 'CCCCCCCCCCCCCCCCCCCCCC'; // revocado
  const T_CADUCADO = 'DDDDDDDDDDDDDDDDDDDDDD';

  const linkDoc = (overrides = {}) => ({
    sessionId: 's1', accountId: 'a1', ticketId: 't1',
    merchantName: 'Mercadona',
    manuals: [{ pid: 'p5', manualId: 'm1', displayName: 'Marta' }],
    createdByUid: OWNER, status: 'active',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  });

  /** Acceso como participante YA reclamado por ese UID (cuenta/invitado). */
  const openAsKnown = (f, uid, token, { pid = 'p2', ticketId = 't1' } = {}) =>
    setDoc(doc(f, `${S}/ticketAccess/${ticketId}_${uid}`), {
      uid, token, ticketId, pid,
      createdAt: serverTimestamp(), schemaVersion: 1,
    });

  /** Paso 2: identificarse como un MANUAL (prueba + cerrojo en un batch). */
  const identify = (f, uid, token, { pid = 'p5', manualId = 'm1',
      ticketId = 't1', claimUid = uid } = {}) => {
    const batch = writeBatch(f);
    batch.set(doc(f, `${S}/ticketClaims/${ticketId}_${manualId}`), {
      uid: claimUid, ticketId, manualId,
      createdAt: serverTimestamp(), schemaVersion: 1,
    });
    batch.set(doc(f, `${S}/ticketAccess/${ticketId}_${uid}`), {
      uid, token, ticketId, pid, manualId,
      createdAt: serverTimestamp(), schemaVersion: 1,
    });
    return batch.commit();
  };

  beforeEach(async () => {
    await seedSocialProfiles();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `${S}/participants/p5`), {
        name: 'Marta', isOwner: false, order: 4, active: true,
        claimedByDevice: '', manualId: 'm1',
      });
      await setDoc(doc(f, `${S}/participants/p6`), {
        name: 'Tío Luis', isOwner: false, order: 5, active: true,
        claimedByDevice: '', manualId: 'm2',
      });
      // Segundo ticket de la MISMA sesión, para probar el aislamiento.
      await setDoc(doc(f, `${S}/accounts/a1/tickets/t2`), {
        kind: 'manual', grandTotal: 500, paidByParticipantId: 'p1',
        merchant: { name: 'Otro' },
      });
      // Proyeccion AUTORITATIVA que escribe recompute: quien participa en
      // cada ticket. Las Rules la consultan en vez de fiarse del enlace.
      for (const [tid, pid] of [
        ['t1', 'p1'], ['t1', 'p2'], ['t1', 'p5'], ['t1', 'p6'],
        ['t2', 'p1'], ['t2', 'p5'],
      ]) {
        await setDoc(doc(f, `${S}/ticketParticipants/${tid}_${pid}`),
          { ticketId: tid, pid, schemaVersion: 1 });
      }
      // Señal de proyección PREPARADA, que recompute escribe en el mismo
      // batch que las entradas. Sin ella no se puede crear un enlace.
      for (const tid of ['t1', 't2']) {
        await setDoc(doc(f, `${S}/ticketParticipantProjections/${tid}`), {
          ticketId: tid, ready: true, fingerprint: 'x',
          updatedAt: serverTimestamp(), schemaVersion: 1,
        });
      }
      await setDoc(doc(f, `ticketLinks/${T}`), linkDoc());
      await setDoc(doc(f, `ticketLinks/${T_OTRO}`),
        linkDoc({ ticketId: 't2', merchantName: 'Otro' }));
      await setDoc(doc(f, `ticketLinks/${T_MUERTO}`),
        linkDoc({ status: 'revoked' }));
      await setDoc(doc(f, `ticketLinks/${T_CADUCADO}`),
        linkDoc({ expiresAt: new Date(Date.now() - 60000) }));
      await setDoc(doc(f, `guestIdentities/${GUEST}`), {
        uid: GUEST, displayName: 'Alba invitada',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
    });
  });

  // ── Gobierno del enlace ─────────────────────────────────────────────
  it('solo el dueño de la sesión crea el enlace, y hacia SU ticket', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), 'ticketLinks/NUEVOAAAAAAAAAAAAAAAA'),
      linkDoc({ createdByUid: OWNER })));
    // Un participante cualquiera, no.
    await assertFails(setDoc(doc(db(STRANGER), 'ticketLinks/DEOTROAAAAAAAAAAAAAAA'),
      linkDoc({ createdByUid: STRANGER })));
    // Apuntar a un ticket que no existe donde dice: denegado.
    await assertFails(setDoc(doc(db(OWNER), 'ticketLinks/FANTASMAAAAAAAAAAAAAA'),
      linkDoc({ ticketId: 'no-existe' })));
  });

  it('el enlace NO es enumerable', async () => {
    await assertFails(getDocs(collection(db(STRANGER), 'ticketLinks')));
    await assertFails(getDocs(query(collection(db(FOURTH), 'ticketLinks'),
      where('sessionId', '==', 's1'))));
    await assertSucceeds(getDocs(query(collection(db(OWNER), 'ticketLinks'),
      where('sessionId', '==', 's1'), where('status', '==', 'active'))));
  });

  it('quien recibe el enlace ve el comercio, nada más', async () => {
    await assertSucceeds(getDoc(doc(db(FOURTH), `ticketLinks/${T}`)));
    // Pero sin identificarse no lee ni el ticket ni la sesión.
    await assertFails(getDoc(doc(db(FOURTH), `${S}/accounts/a1/tickets/t1`)));
    await assertFails(getDoc(doc(db(FOURTH), S)));
  });

  it('reapuntar el enlace a otro ticket es un secuestro: denegado', async () => {
    await assertFails(updateDoc(doc(db(OWNER), `ticketLinks/${T}`),
      { ticketId: 't2', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `ticketLinks/${T}`),
      { status: 'revoked', updatedAt: serverTimestamp() }));
  });

  // ── Acceso de lectura ───────────────────────────────────────────────
  it('poseer el enlace NO basta: hay que representar a alguien del ticket',
      async () => {
    const f = db(FOURTH);
    // Sin identificarse, el enlace no abre nada.
    await assertFails(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
    // Ni se puede fabricar un acceso "en blanco".
    await assertFails(setDoc(doc(f, `${S}/ticketAccess/t1_${FOURTH}`), {
      uid: FOURTH, token: T, ticketId: 't1', pid: '',
      createdAt: serverTimestamp(), schemaVersion: 1,
    }));
    // Tras elegir un MANUAL valido, si.
    await assertSucceeds(identify(f, FOURTH, T));
    await assertSucceeds(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
    await assertSucceeds(getDocs(collection(f, `${S}/accounts/a1/tickets/t1/lines`)));
    // Pero los participantes de la sesion siguen sin abrirse.
    await assertFails(getDocs(collection(f, `${S}/participants`)));
  });

  it('una cuenta/invitado ya participante entra sin elegir MANUAL', async () => {
    await assertSucceeds(openAsKnown(db(GUEST), GUEST, T));
    await assertSucceeds(
      getDoc(doc(db(GUEST), `${S}/accounts/a1/tickets/t1`)));
    // Un desconocido no puede colgarse de un participante ajeno.
    await assertFails(openAsKnown(db(FOURTH), FOURTH, T, { pid: 'p2' }));
  });

  it('un pid que NO participa en el ticket es rechazado', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${S}/participants/p7`), {
        name: 'Ajeno', isOwner: false, order: 6, active: true,
        claimedByDevice: '', manualId: 'm9',
      });
    });
    await assertFails(identify(db(FOURTH), FOURTH, T,
      { pid: 'p7', manualId: 'm9' }));
  });

  it('el enlace NO da acceso al resto: ni otro ticket, ni la sesión, ni el grupo',
      async () => {
    const f = db(FOURTH);
    await identify(f, FOURTH, T);
    // Otro ticket de la MISMA sesión: fuera.
    await assertFails(getDoc(doc(f, `${S}/accounts/a1/tickets/t2`)));
    // La sesión (con sus balances) y las liquidaciones: fuera.
    await assertFails(getDoc(doc(f, S)));
    await assertFails(getDocs(collection(f, `${S}/settlements`)));
    // Y nada del espacio: ni miembros ni membresía.
    await assertFails(getDocs(collection(f, 'spaces/sp1/members')));
    await assertFails(setDoc(doc(f, `spaces/sp1/members/${FOURTH}`),
      { uid: FOURTH, joinedAt: serverTimestamp() }));
  });

  it('abrir un 2o ticket NO invalida el acceso al 1o', async () => {
    const f = db(FOURTH);
    await assertSucceeds(identify(f, FOURTH, T));
    await assertSucceeds(identify(f, FOURTH, T_OTRO, { ticketId: 't2' }));
    // La clave incluye ticketId, asi que el primero SIGUE vivo.
    await assertSucceeds(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
    await assertSucceeds(getDoc(doc(f, `${S}/accounts/a1/tickets/t2`)));
  });

  it('enlace revocado o caducado: ni acceso ni identificación', async () => {
    await assertFails(identify(db(FOURTH), FOURTH, T_MUERTO));
    await assertFails(identify(db(FOURTH), FOURTH, T_CADUCADO));
    await assertFails(openAsKnown(db(GUEST), GUEST, T_MUERTO));
  });

  it('revocar el enlace corta la lectura ya concedida', async () => {
    const f = db(FOURTH);
    await identify(f, FOURTH, T);
    await assertSucceeds(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), `ticketLinks/${T}`),
        { status: 'revoked', updatedAt: serverTimestamp() });
    });
    // La prueba sigue escrita, pero se revalida el enlace en CADA lectura.
    await assertFails(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
  });

  // ── Identificación temporal como MANUAL ─────────────────────────────
  it('identificarse como un MANUAL del ticket funciona', async () => {
    await assertSucceeds(identify(db(FOURTH), FOURTH, T));
  });

  it('NO se puede suplantar a una cuenta ni a un invitado', async () => {
    // p2 lo reclamó GUEST (cuenta/invitado): no tiene manualId.
    await assertFails(identify(db(FOURTH), FOURTH, T,
      { pid: 'p2', manualId: 'm1' }));
    // p1 es el anfitrión.
    await assertFails(identify(db(FOURTH), FOURTH, T,
      { pid: 'p1', manualId: 'm1' }));
  });

  it('el pid y el manualId tienen que corresponderse de verdad', async () => {
    // p5 es m1, no m2: declarar otro manualId no cuela.
    await assertFails(identify(db(FOURTH), FOURTH, T,
      { pid: 'p5', manualId: 'm2' }));
  });

  it('no se puede crear la identificación para OTRO uid', async () => {
    const f = db(FOURTH);
    await assertFails(setDoc(doc(f, `${S}/ticketAccess/t1_${THIRD}`), {
      uid: THIRD, token: T, ticketId: 't1', pid: 'p5', manualId: 'm1',
      createdAt: serverTimestamp(), schemaVersion: 1,
    }));
    // Ni con el cerrojo a nombre de otro.
    await assertFails(identify(f, FOURTH, T, { claimUid: THIRD }));
  });

  it('la identificación es PRIVADA: solo la lee su dueño', async () => {
    await identify(db(FOURTH), FOURTH, T);
    await assertFails(getDoc(doc(db(THIRD), `${S}/ticketAccess/t1_${FOURTH}`)));
    // Ni el dueño de la sesión audita quién dice ser quién.
    await assertFails(getDoc(doc(db(OWNER), `${S}/ticketAccess/t1_${FOURTH}`)));
    await assertFails(getDocs(collection(db(OWNER), `${S}/ticketAccess`)));
  });

  it('dos dispositivos no pueden quedarse con el MISMO manual', async () => {
    await assertSucceeds(identify(db(FOURTH), FOURTH, T));
    // El segundo choca con el cerrojo determinista: primero en llegar gana.
    await assertFails(identify(db(THIRD), THIRD, T));
    // Y sigue pudiendo coger OTRO manual libre.
    await assertSucceeds(identify(db(THIRD), THIRD, T,
      { pid: 'p6', manualId: 'm2' }));
  });

  it('reabrir el mismo enlace en el mismo dispositivo es idempotente', async () => {
    await assertSucceeds(identify(db(FOURTH), FOURTH, T));
    await assertSucceeds(identify(db(FOURTH), FOURTH, T));
  });

  it('un MANUAL ya VINCULADO deja de ser elegible', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      // El enlace apunta a un espacio y m1 aparece ya vinculado (Sprint 6).
      await setDoc(doc(f, `ticketLinks/${T}`), linkDoc({ spaceId: 'sp1' }));
      await setDoc(doc(f, 'spaces/sp1/manualParticipants/m1'), {
        manualId: 'm1', displayName: 'Marta', linkedUid: FOURTH,
        createdByUid: SOCIAL_OUTSIDER, createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(), schemaVersion: 1,
      });
    });
    await assertFails(identify(db(FOURTH), FOURTH, T));
  });

  it('el flujo de acceso NO puede tocar balances ni participantes', async () => {
    const f = db(FOURTH);
    await identify(f, FOURTH, T);
    // Agregados: solo-lectura para todo cliente, tambien por enlace.
    await assertFails(updateDoc(doc(f, S), { balances: {} }));
    // Los participantes originales del ticket no se tocan.
    await assertFails(updateDoc(doc(f, `${S}/participants/p5`),
      { name: 'Otro' }));
    await assertFails(updateDoc(doc(f, `${S}/participants/p5`),
      { claimedByDevice: FOURTH }));
    // Ni las lineas del ticket.
    await assertFails(setDoc(doc(f, `${S}/accounts/a1/tickets/t1/lines/nueva`),
      { name: 'Colada', totalPrice: 100, order: 99 }));
  });

  it('un anónimo SIN identidad de invitado no abre enlaces de ticket', async () => {
    await assertFails(identify(db(OTHER), OTHER, T));
  });

  it('RECUPERACION: el dueño libera una reclamación errónea o maliciosa',
      async () => {
    await assertSucceeds(identify(db(FOURTH), FOURTH, T));
    await assertFails(identify(db(THIRD), THIRD, T));
    // El dueño de la sesión retira cerrojo y prueba...
    await assertSucceeds(deleteDoc(doc(db(OWNER), `${S}/ticketClaims/t1_m1`)));
    await assertSucceeds(
      deleteDoc(doc(db(OWNER), `${S}/ticketAccess/t1_${FOURTH}`)));
    // ...y el sitio queda libre otra vez.
    await assertSucceeds(identify(db(THIRD), THIRD, T));
    // El usurpador pierde el acceso.
    await assertFails(getDoc(doc(db(FOURTH), `${S}/accounts/a1/tickets/t1`)));
  });

  it('un enlace NO puede nacer si la proyección aún no está preparada',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Ticket recién creado: recompute todavía no ha proyectado nada.
      const f = ctx.firestore();
      await setDoc(doc(f, `${S}/accounts/a1/tickets/t9`), {
        kind: 'manual', grandTotal: 100, paidByParticipantId: 'p1',
        merchant: { name: 'Recien' },
      });
    });
    // Así se resuelve la carrera: NO se crea un enlace que después fallaría.
    await assertFails(setDoc(doc(db(OWNER), 'ticketLinks/SINPROYECCIONAAAAAAAA'),
      linkDoc({ ticketId: 't9', merchantName: 'Recien' })));

    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `${S}/ticketParticipantProjections/t9`),
        { ticketId: 't9', ready: true, fingerprint: 'y',
          updatedAt: serverTimestamp(), schemaVersion: 1 });
    });
    // Ya preparada: ahora sí.
    await assertSucceeds(setDoc(doc(db(OWNER), 'ticketLinks/CONPROYECCIONAAAAAAAA'),
      linkDoc({ ticketId: 't9', merchantName: 'Recien' })));
  });

  it('una entrada OBSOLETA de la proyección deja de conceder acceso',
      async () => {
    const f = db(FOURTH);
    await assertSucceeds(identify(f, FOURTH, T));
    await assertSucceeds(getDoc(doc(f, `${S}/accounts/a1/tickets/t1`)));
    // recompute rehace el reparto y p5 deja de participar: borra su entrada.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `${S}/ticketParticipants/t1_p5`));
    });
    // La identificación antigua ya no autoriza: se revalida en cada uso.
    await assertFails(identify(f, FOURTH, T));
  });

  it('sin proyección NO hay fallback al array `manuals` del enlace',
      async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      // El enlace SIGUE anunciando a Marta, pero la proyección ya no la tiene.
      await deleteDoc(doc(ctx.firestore(), `${S}/ticketParticipants/t1_p5`));
    });
    // Si existiera fallback, esto pasaría. No existe.
    await assertFails(identify(db(FOURTH), FOURTH, T));
  });

  it('la señal de preparación NO la escribe ningún cliente', async () => {
    await assertFails(setDoc(
      doc(db(OWNER), `${S}/ticketParticipantProjections/t1`),
      { ticketId: 't1', ready: true, schemaVersion: 1 }));
    await assertFails(setDoc(
      doc(db(FOURTH), `${S}/ticketParticipantProjections/t9`),
      { ticketId: 't9', ready: true, schemaVersion: 1 }));
  });

  it('la proyección de participación NO la escribe ningún cliente', async () => {
    await assertFails(setDoc(doc(db(OWNER), `${S}/ticketParticipants/t1_p9`),
      { ticketId: 't1', pid: 'p9', schemaVersion: 1 }));
    await assertFails(setDoc(doc(db(FOURTH), `${S}/ticketParticipants/t1_p9`),
      { ticketId: 't1', pid: 'p9', schemaVersion: 1 }));
  });
});

// Nota: assert está importado para fallos explícitos en helpers futuros.
void assert;
