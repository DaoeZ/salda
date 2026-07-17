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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
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

// ─── Sesiones: crear ────────────────────────────────────────────────────
describe('sessions.create', () => {
  const valid = {
    ownerUid: OWNER, kind: 'single', name: 'Cena', status: 'open',
    splitModeDefault: 'equal', shareCode: 'OTRO-CODIGO-16CH', currency: 'EUR',
    computeVersion: 0,
  };

  it('owner crea una sesión válida', () =>
    assertSucceeds(setDoc(doc(db(OWNER), 'sessions/nueva'), valid)));

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

// Nota: assert está importado para fallos explícitos en helpers futuros.
void assert;
