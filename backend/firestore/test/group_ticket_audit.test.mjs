/**
 * A11b: auditoría del ticket por el grupo.
 *
 * La foto y el desglose de un gasto compartido son EVIDENCIA, no un archivo
 * privado de quien lo subió: cualquier miembro del grupo tiene que poder
 * comprobar que la línea interpretada coincide con el papel. Estas pruebas
 * fijan las dos mitades del contrato: la lectura se abre al grupo y la
 * escritura NO se mueve ni un milímetro.
 *
 * Ejecutar desde la raíz del repo:
 *   firebase emulators:exec --only firestore --project demo-salda \
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
  deleteField,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

// Quién es quién. El grupo `gr1` lo preside JEFA; ALBA sube el ticket y
// JORGE es un miembro normal que no consume nada de él.
const JEFA = 'uid-jefa';
const ALBA = 'uid-alba';
const JORGE = 'uid-jorge';
const ADMIN = 'uid-admin'; // miembro de gr1 con role: admin
const AJENA = 'uid-ajena'; // miembro de OTRO grupo
const EXTERNO = 'uid-externo'; // cuenta verificada sin relación alguna
const PAREJA = 'uid-pareja'; // la otra mitad de la relación rel1

const SG = 'sessions/sg1'; // sesión contextual del grupo gr1
const T = `${SG}/accounts/a1/tickets/t1`;
const SR = 'sessions/sr1'; // sesión contextual de la RELACIÓN rel1
const SL = 'sessions/sl1'; // sesión LEGACY, sin contexto

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

    // Identidad pública: sin ella no hay canUseSocial().
    for (const uid of [JEFA, ALBA, JORGE, ADMIN, AJENA, EXTERNO, PAREJA]) {
      await setDoc(doc(f, `profiles/${uid}`), {
        displayName: uid, displayNameLower: uid, username: uid,
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        schemaVersion: 1,
      });
    }

    // Grupo con cuatro miembros.
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

    // Otro grupo, sin nada que ver con el primero.
    await setDoc(doc(f, 'spaces/gr2'), {
      name: 'Otro', ownerUid: AJENA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    await setDoc(doc(f, `spaces/gr2/members/${AJENA}`), {
      uid: AJENA, joinedAt: serverTimestamp(),
    });

    // Relación: su modelo NO cambia con A11b.
    await setDoc(doc(f, 'spaces/rel1'), {
      name: 'Jefa y pareja', ownerUid: JEFA, kind: 'relationship',
      relationshipUids: [JEFA, PAREJA].sort(), status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    for (const uid of [JEFA, PAREJA]) {
      await setDoc(doc(f, `spaces/rel1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
      });
    }

    // El ticket de Alba, nacido DENTRO del grupo (ADR-030).
    await setDoc(doc(f, SG), {
      ownerUid: ALBA, kind: 'multi', name: 'Compra', status: 'open',
      splitModeDefault: 'byItem', shareCode: 'SECRET-CODE-16CHARS',
      currency: 'EUR', contextModelVersion: 1, spaceId: 'gr1',
      computeVersion: 0, totals: { grandTotal: 550 }, balances: {},
    });
    await setDoc(doc(f, `${SG}/participants/p1`), {
      name: 'Alba', isOwner: true, order: 0, claimedByDevice: '',
    });
    // Jorge entra en el reparto con su UID reclamado, como cualquier miembro
    // del grupo que el anfitrión añade al gasto (ADR-030).
    await setDoc(doc(f, `${SG}/participants/p2`), {
      name: 'Jorge', isOwner: false, order: 1, claimedByDevice: JORGE,
    });
    await setDoc(doc(f, `${SG}/accounts/a1`), { name: 'Súper', order: 0 });
    await setDoc(doc(f, T), {
      kind: 'scanned', grandTotal: 550, paidByParticipantId: 'p1',
      imagePath: 'receipts/sg1/t1/original.jpg',
      merchant: { name: 'Familycash' },
      spaceId: 'gr1', contextModelVersion: 1,
    });
    // Jorge no consume NADA de este ticket: aun así debe poder auditarlo.
    await setDoc(doc(f, `${T}/lines/l1`), {
      name: 'Coca-Cola', totalPrice: 250, quantityMilli: 1000, order: 0,
      assignment: { type: 'units', schemaVersion: 2, units: { u0: { p1: true } } },
    });
    await setDoc(doc(f, `${T}/lines/l2`), {
      name: 'Patatas', totalPrice: 300, quantityMilli: 1000, order: 1,
      unitIds: ['u0'],
      assignment: { type: 'units', schemaVersion: 2, units: {} },
    });
    await setDoc(doc(f, `${SG}/settlements/st1`), {
      from: 'p2', to: 'p1', amount: 250, state: 'pending',
    });

    // Mismo montaje dentro de una RELACIÓN.
    await setDoc(doc(f, SR), {
      ownerUid: JEFA, kind: 'single', name: 'Cena', status: 'open',
      splitModeDefault: 'equal', shareCode: 'SECRET-CODE-16CHARS',
      currency: 'EUR', contextModelVersion: 1, spaceId: 'rel1',
      computeVersion: 0, totals: { grandTotal: 900 }, balances: {},
    });
    await setDoc(doc(f, `${SR}/accounts/a1`), { name: 'Cena', order: 0 });
    await setDoc(doc(f, `${SR}/accounts/a1/tickets/t1`), {
      kind: 'manual', grandTotal: 900, paidByParticipantId: 'p1',
      spaceId: 'rel1', contextModelVersion: 1,
    });
    await setDoc(doc(f, `${SR}/accounts/a1/tickets/t1/lines/l1`), {
      name: 'Menú', totalPrice: 900,
      assignment: { type: 'unassigned', participants: {} },
    });

    // Sesión LEGACY (sin contexto) cuyo ticket se vinculó a mano al grupo.
    await setDoc(doc(f, SL), {
      ownerUid: ALBA, kind: 'single', name: 'Antiguo', status: 'open',
      splitModeDefault: 'equal', shareCode: 'SECRET-CODE-16CHARS',
      currency: 'EUR', computeVersion: 0,
    });
    await setDoc(doc(f, `${SL}/accounts/a1`), { name: 'Antiguo', order: 0 });
    await setDoc(doc(f, `${SL}/accounts/a1/tickets/t1`), {
      kind: 'manual', grandTotal: 100, paidByParticipantId: 'p1',
      spaceId: 'gr1',
    });
    await setDoc(doc(f, `${SL}/accounts/a1/tickets/t1/lines/l1`), {
      name: 'Café', totalPrice: 100,
      assignment: { type: 'unassigned', participants: {} },
    });
  });
});

describe('A11b: el grupo audita el ticket', () => {
  it('un miembro normal lee ticket, líneas, cuentas y participantes', async () => {
    const f = db(JORGE);
    await assertSucceeds(getDoc(doc(f, T)));
    await assertSucceeds(getDocs(collection(f, `${T}/lines`)));
    await assertSucceeds(getDocs(collection(f, `${SG}/accounts`)));
    await assertSucceeds(getDocs(collection(f, `${SG}/participants`)));
    // Y llega al ticket recorriendo las cuentas, que es lo que hace la app.
    await assertSucceeds(getDocs(collection(f, `${SG}/accounts/a1/tickets`)));
  });

  it('lo lee aunque no consuma nada de ese ticket', async () => {
    // l1 está asignada entera a p1 (Alba) y l2 a nadie: Jorge no aparece.
    const linea = await getDoc(doc(db(JORGE), `${T}/lines/l1`));
    if (linea.data().name !== 'Coca-Cola') {
      throw new Error('la línea no llegó completa al auditor');
    }
  });

  it('el propietario del grupo y un administrador también leen', async () => {
    for (const uid of [JEFA, ADMIN]) {
      await assertSucceeds(getDoc(doc(db(uid), T)));
      await assertSucceeds(getDocs(collection(db(uid), `${T}/lines`)));
    }
  });

  it('el dueño de la sesión conserva su lectura y su escritura', async () => {
    const f = db(ALBA);
    await assertSucceeds(getDoc(doc(f, T)));
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l1`), {
      name: 'Coca-Cola Zero',
    }));
  });

  // ── La otra mitad del contrato: leer NO es escribir ──────────────────
  // Ojo al alcance: desde A11c, quien ADMINISTRA el grupo sí corrige el
  // contenido del ticket (su autoridad y sus límites están en
  // group_ticket_correction.test.mjs). Lo que A11b fija es que auditar, por
  // sí solo, no escribe nada: eso se comprueba con el miembro normal.
  it('el auditor no toca una sola línea del ticket ajeno', async () => {
    const f = db(JORGE);
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), { totalPrice: 1 }));
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), { name: 'Otro' }));
    await assertFails(deleteDoc(doc(f, `${T}/lines/l1`)));
    await assertFails(setDoc(doc(f, `${T}/lines/nueva`), {
      name: 'Inventada', totalPrice: 100,
    }));
    // Y ni siquiera el administrador puede INVENTAR un producto: añadir
    // líneas sigue siendo del dueño de la sesión.
    for (const uid of [JEFA, ADMIN]) {
      await assertFails(setDoc(doc(db(uid), `${T}/lines/nueva`), {
        name: 'Inventada', totalPrice: 100,
      }));
    }
  });

  it('tampoco el ticket, la cuenta, el participante ni la sesión', async () => {
    const f = db(JORGE);
    await assertFails(updateDoc(doc(f, T), { grandTotal: 1 }));
    await assertFails(updateDoc(doc(f, T), { spaceId: 'gr2' }));
    await assertFails(deleteDoc(doc(f, T)));
    await assertFails(updateDoc(doc(f, `${SG}/accounts/a1`), { name: 'X' }));
    await assertFails(updateDoc(doc(f, `${SG}/participants/p1`), {
      claimedByDevice: JORGE,
    }));
    await assertFails(updateDoc(doc(f, SG), { status: 'closed' }));
    await assertFails(deleteDoc(doc(f, SG)));
  });

  // El documento de sesión guarda el `shareCode`: leerlo permitiría
  // fabricarse un guestAccess y con él EDITAR. Ampliar la lectura no puede
  // ampliar la escritura por la puerta de atrás.
  it('el grupo NO lee el documento de sesión (shareCode)', async () => {
    for (const uid of [JORGE, JEFA, ADMIN]) {
      await assertFails(getDoc(doc(db(uid), SG)));
    }
    // Por qué importa: el shareCode ES la credencial de invitado (ADR-012).
    // Quien lo conoce se da de alta como tal y con ello puede EDITAR líneas.
    // A11b no toca ese mecanismo; lo que hace es no regalar el secreto.
    await assertSucceeds(setDoc(doc(db(JORGE), `${SG}/guestAccess/${JORGE}`), {
      shareCode: 'SECRET-CODE-16CHARS',
    }));
  });

  it('la auditoría no arrastra liquidaciones ni actividad de la sesión', async () => {
    const f = db(JORGE);
    await assertFails(getDocs(collection(f, `${SG}/settlements`)));
    await assertFails(getDocs(collection(f, `${SG}/activity`)));
  });

  // ── Elegir MI consumo no es editar el ticket ─────────────────────────
  // Jorge (p2) está reclamado por su UID, igual que un invitado reclama su
  // nombre: la misma puerta de siempre, con la misma cerradura.
  it('el miembro marca y desmarca SU consumo en una línea del ticket', async () => {
    const f = db(JORGE);
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
    }));
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': deleteField(),
    }));
  });

  it('no puede marcar por otro ni retirar lo que otro marcó', async () => {
    const f = db(JORGE);
    // Firmar como Alba: el pid no está reclamado por su UID.
    await assertFails(updateDoc(doc(f, `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p1',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p1': true,
    }));
    // Firmar como él mismo pero tocar la entrada de otro.
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p1': deleteField(),
    }));
  });

  it('marcar consumo NO abre la puerta a editar el dato fuente', async () => {
    const f = db(JORGE);
    // Colar el precio en la misma escritura que la asignación.
    await assertFails(updateDoc(doc(f, `${T}/lines/l2`), {
      totalPrice: 1,
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
    }));
    await assertFails(updateDoc(doc(f, `${T}/lines/l2`), { name: 'Caviar' }));
  });

  it('en un ticket a medias no se elige nada', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), T), { splitModeOverride: 'equal' });
    });
    await assertFails(updateDoc(doc(db(JORGE), `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
    }));
  });

  it('con la sesión cerrada tampoco', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), SG), { status: 'closed' });
    });
    await assertFails(updateDoc(doc(db(JORGE), `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
    }));
  });

  it('el propietario del grupo no elige por nadie: no es participante', async () => {
    // JEFA preside el grupo pero no está en este ticket. Administrar no es
    // consumir, y A11c no ha llegado.
    await assertFails(updateDoc(doc(db(JEFA), `${T}/lines/l2`), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
    }));
  });

  // ── Fuera del grupo no hay nada que ver ──────────────────────────────
  it('un miembro de OTRO grupo no lee nada', async () => {
    const f = db(AJENA);
    await assertFails(getDoc(doc(f, T)));
    await assertFails(getDocs(collection(f, `${T}/lines`)));
    await assertFails(getDocs(collection(f, `${SG}/participants`)));
    await assertFails(getDocs(collection(f, `${SG}/accounts`)));
  });

  it('un externo total tampoco, ni conociendo la ruta exacta', async () => {
    const f = db(EXTERNO);
    await assertFails(getDoc(doc(f, T)));
    await assertFails(getDoc(doc(f, `${T}/lines/l1`)));
    await assertFails(getDocs(collection(f, `${SG}/accounts`)));
    await assertFails(getDoc(doc(f, SG)));
  });

  it('ni el externo ni el de otro grupo pueden marcar consumo', async () => {
    for (const uid of [EXTERNO, AJENA]) {
      await assertFails(updateDoc(doc(db(uid), `${T}/lines/l2`), {
        'assignment.type': 'units',
        'assignment.schemaVersion': 2,
        'assignment.lastEditorPid': 'p2',
        'assignment.lastEditedUnit': 'u0',
        'assignment.units.u0.p2': true,
      }));
    }
  });

  // ── Lo que NO entra en la auditoría de grupo ─────────────────────────
  it('una RELACIÓN mantiene su comportamiento: no se audita como grupo', async () => {
    const f = db(PAREJA);
    await assertFails(getDoc(doc(f, `${SR}/accounts/a1/tickets/t1/lines/l1`)));
    await assertFails(getDocs(collection(f, `${SR}/participants`)));
    // El dueño de la sesión sigue leyendo la suya con normalidad.
    await assertSucceeds(
      getDoc(doc(db(JEFA), `${SR}/accounts/a1/tickets/t1/lines/l1`)));
  });

  it('una sesión SIN contexto no se abre por vincular un ticket a mano', async () => {
    const f = db(JORGE);
    // El RESUMEN del ticket vinculado sí se ve (P4), y eso no cambia.
    await assertSucceeds(getDoc(doc(f, `${SL}/accounts/a1/tickets/t1`)));
    // Pero la sesión legacy no se convierte en material del grupo.
    await assertFails(getDoc(doc(f, `${SL}/accounts/a1/tickets/t1/lines/l1`)));
    await assertFails(getDocs(collection(f, `${SL}/accounts`)));
  });

  it('quien deja de ser miembro deja de auditar', async () => {
    await assertSucceeds(getDoc(doc(db(JORGE), T)));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
    });
    await assertFails(getDoc(doc(db(JORGE), `${T}/lines/l1`)));
  });
});
