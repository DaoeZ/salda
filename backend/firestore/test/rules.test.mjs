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
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let env;

const OWNER = 'owner-uid';
const GUEST = 'guest-uid'; // anónimo con guestAccess concedido
const OTHER = 'other-guest-uid'; // anónimo que reclamó p3
const STRANGER = 'stranger-uid'; // autenticado SIN guestAccess
const CODE = 'SECRET-CODE-16CHARS';

const db = (uid) =>
  uid === null
    ? env.unauthenticatedContext().firestore()
    : env.authenticatedContext(uid).firestore();

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
    // Sesión cerrada para probar el bloqueo total.
    await setDoc(doc(f, 'sessions/s2'), {
      ownerUid: OWNER, kind: 'single', name: 'Cerrada', status: 'closed',
      splitModeDefault: 'equal', shareCode: CODE, currency: 'EUR',
      computeVersion: 3,
    });
    await setDoc(doc(f, 'sessions/s2/participants/p1'), {
      name: 'Edgar', isOwner: true, claimedByDevice: '',
    });
    await setDoc(doc(f, 'users/owner-uid'), { displayName: 'Edgar' });
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

// ─── Sesiones: crear ────────────────────────────────────────────────────
describe('sessions.create', () => {
  const valid = {
    ownerUid: OWNER, kind: 'single', name: 'Cena', status: 'open',
    splitModeDefault: 'equal', shareCode: 'OTRO-CODIGO-16CH', currency: 'EUR',
    computeVersion: 0,
  };

  it('owner crea una sesión válida', () =>
    assertSucceeds(setDoc(doc(db(OWNER), 'sessions/nueva'), valid)));

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

  it('el owner confirma y puede forzar cualquier estado', async () => {
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st1`),
      { state: 'confirmed' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `${S}/settlements/st1`),
      { state: 'pending' }));
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
});

// Nota: assert está importado para fallos explícitos en helpers futuros.
void assert;
