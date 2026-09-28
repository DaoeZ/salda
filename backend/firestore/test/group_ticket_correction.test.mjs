/**
 * A11c: corrección administrativa del gasto.
 *
 * Quien administra el grupo arregla el ticket de otro —el precio mal leído,
 * el nombre, la cantidad— y nada más. Estas pruebas fijan las tres fronteras
 * que importan: quién puede corregir, qué puede tocar, y que corregir un
 * gasto NO da ninguna autoridad sobre el dinero de nadie.
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
  deleteDoc,
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

const JEFA = 'uid-jefa'; // propietaria del grupo
const ADMIN = 'uid-admin'; // miembro con role: admin
const ALBA = 'uid-alba'; // subió el ticket (dueña de la sesión)
const JORGE = 'uid-jorge'; // miembro normal
const AJENA = 'uid-ajena'; // administra OTRO grupo
const EXTERNO = 'uid-externo';
const PAREJA = 'uid-pareja'; // la otra mitad de una relación

const SG = 'sessions/sg1';
const T = `${SG}/accounts/a1/tickets/t1`;
const SR = 'sessions/sr1'; // sesión de la RELACIÓN
const TR = `${SR}/accounts/a1/tickets/t1`;

const db = (uid) =>
  env
    .authenticatedContext(uid, {
      email: `${uid}@salda.test`,
      email_verified: true,
      firebase: { sign_in_provider: 'password' },
    })
    .firestore();

/// Corrección de cabecera tal y como la escribe la app: contenido + firma.
const cabecera = (extra = {}) => ({
  'merchant.name': 'Familycash',
  grandTotal: 1696,
  lastEditedByUid: ADMIN,
  lastEditedAt: serverTimestamp(),
  ...extra,
});

/// Corrección de un producto: contenido, y el precio unitario se retira
/// porque deja de ser cierto.
const producto = (extra = {}) => ({
  name: 'Coca-Cola',
  quantityMilli: 1000,
  totalPrice: 400,
  unitPrice: deleteField(),
  ...extra,
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
  });
});
after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of [JEFA, ADMIN, ALBA, JORGE, AJENA, EXTERNO, PAREJA]) {
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
    // Otro grupo: su administradora no pinta nada aquí.
    await setDoc(doc(f, 'spaces/gr2'), {
      name: 'Otro', ownerUid: AJENA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    await setDoc(doc(f, `spaces/gr2/members/${AJENA}`), {
      uid: AJENA, joinedAt: serverTimestamp(),
    });
    // Relación: no tiene administradores y no los adquiere por esta vía.
    await setDoc(doc(f, 'spaces/rel1'), {
      name: 'Pareja', ownerUid: JEFA, kind: 'relationship',
      relationshipUids: [JEFA, PAREJA].sort(), status: 'active',
      createdAt: serverTimestamp(), schemaVersion: 2,
    });
    for (const uid of [JEFA, PAREJA]) {
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
      await setDoc(doc(f, `sessions/${sid}/participants/p1`), {
        name: 'Alba', isOwner: true, order: 0, claimedByDevice: ALBA,
      });
      await setDoc(doc(f, `sessions/${sid}/participants/p2`), {
        name: 'Jorge', isOwner: false, order: 1, claimedByDevice: JORGE,
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1`), {
        name: 'Súper', order: 0,
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1`), {
        kind: 'scanned', grandTotal: 1596, paidByParticipantId: 'p1',
        merchant: { name: 'Familycas' }, spaceId, contextModelVersion: 1,
        splitModeOverride: 'byItem',
      });
      // Dos unidades con dueño: la unidad 2 es la que se pierde al reducir.
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1/lines/l1`), {
        name: 'Coca-Cola', totalPrice: 300, quantityMilli: 2000, order: 0,
        unitPrice: 150, unitIds: ['u0', 'u1'],
        assignment: {
          type: 'units', schemaVersion: 2,
          units: { u0: { p1: true }, u1: { p2: true } },
        },
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1/lines/l2`), {
        name: 'Patatas', totalPrice: 1296, quantityMilli: 1000, order: 1,
        unitIds: ['u0'],
        assignment: { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } },
      });
    }

    // Liquidación y pago ya existentes: corregir el gasto no los toca.
    await setDoc(doc(f, `${SG}/settlements/st1`), {
      from: 'p2', to: 'p1', amount: 300, state: 'confirmed',
    });
    await setDoc(doc(f, 'economicPayments/pay1'), {
      memberUids: [ALBA, JORGE].sort(), pairId: 'par', payerUid: JORGE,
      receiverUid: ALBA, amount: 300, currency: 'EUR', status: 'confirmed',
      source: 'user', spaceId: 'gr1', sourceSessionId: 'sg1',
      hasManualParty: false, schemaVersion: 1,
    });
  });
});

describe('A11c: corregir el gasto de otro', () => {
  it('el administrador corrige cabecera y producto', async () => {
    const f = db(ADMIN);
    await assertSucceeds(updateDoc(doc(f, T), cabecera()));
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l1`), producto()));
  });

  it('el propietario del grupo también', async () => {
    const f = db(JEFA);
    await assertSucceeds(
      updateDoc(doc(f, T), cabecera({ lastEditedByUid: JEFA })));
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l1`), producto()));
  });

  it('el creador de la sesión conserva su edición de siempre', async () => {
    const f = db(ALBA);
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l1`), {
      name: 'Coca-Cola Zero', totalPrice: 350,
    }));
    await assertSucceeds(updateDoc(doc(f, T), { grandTotal: 1646 }));
  });

  it('un miembro normal no corrige nada', async () => {
    const f = db(JORGE);
    await assertFails(updateDoc(doc(f, T), cabecera({
      lastEditedByUid: JORGE,
    })));
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), producto()));
    await assertFails(deleteDoc(doc(f, `${T}/lines/l2`)));
  });

  it('quien administra OTRO grupo, y un externo, tampoco', async () => {
    for (const uid of [AJENA, EXTERNO]) {
      await assertFails(updateDoc(doc(db(uid), T), cabecera({
        lastEditedByUid: uid,
      })));
      await assertFails(updateDoc(doc(db(uid), `${T}/lines/l1`), producto()));
    }
  });

  it('una RELACIÓN no tiene corrección administrativa', async () => {
    // JEFA es `ownerUid` de la relación: sin la condición de grupo habría
    // heredado la figura de administradora por la puerta de atrás.
    await assertFails(updateDoc(doc(db(JEFA), TR), cabecera({
      lastEditedByUid: JEFA,
    })));
    await assertFails(updateDoc(doc(db(PAREJA), `${TR}/lines/l1`), producto()));
    // Y su dueña de sesión sigue editando como siempre.
    await assertSucceeds(updateDoc(doc(db(ALBA), `${TR}/lines/l1`), {
      totalPrice: 400,
    }));
  });

  // ── Qué puede tocar: lista blanca estrecha ──────────────────────────
  it('la corrección va FIRMADA y no se puede falsear el autor', async () => {
    const f = db(ADMIN);
    await assertFails(updateDoc(doc(f, T), { grandTotal: 1696 }));
    await assertFails(updateDoc(doc(f, T), cabecera({
      lastEditedByUid: ALBA,
    })));
    await assertFails(updateDoc(doc(f, T), {
      grandTotal: 1696,
      lastEditedByUid: ADMIN,
      lastEditedAt: new Date(2020, 1, 1),
    }));
  });

  it('no mueve el gasto de grupo ni decide quién pagó', async () => {
    const f = db(ADMIN);
    await assertFails(updateDoc(doc(f, T), cabecera({ spaceId: 'gr2' })));
    await assertFails(updateDoc(doc(f, T), cabecera({
      paidByParticipantId: 'p2',
    })));
    await assertFails(updateDoc(doc(f, T), cabecera({ imagePath: 'otra.jpg' })));
  });

  it('corregir el precio NO toca el reparto', async () => {
    // Cambiar el importe con las mismas unidades: las asignaciones siguen.
    await assertSucceeds(updateDoc(doc(db(ADMIN), `${T}/lines/l1`), {
      totalPrice: 400, unitPrice: deleteField(),
    }));
  });

  it('no puede repartir el consumo de los demás', async () => {
    const f = db(ADMIN);
    // Meter a Jorge en la unidad de Alba.
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      'assignment.units.u0.p2': true,
    }));
    // Sacar a Jorge de la suya.
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      'assignment.units.u1': deleteField(),
    }));
    // Ni convertir la línea en «para todos».
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      'assignment.type': 'all',
    }));
  });

  it('reducir la cantidad SOLO poda la unidad que desaparece', async () => {
    const f = db(ADMIN);
    // 2 → 1 unidad: se va u1 (la de Jorge) y u0 queda intacta.
    await assertSucceeds(updateDoc(doc(f, `${T}/lines/l1`), {
      name: 'Coca-Cola', quantityMilli: 1000, totalPrice: 150,
      unitPrice: deleteField(), unitIds: ['u0'],
      'assignment.units': { u0: { p1: true } },
    }));
  });

  it('no puede aprovechar la poda para recolocar a nadie', async () => {
    const f = db(ADMIN);
    // Al reducir, trasladar a Jorge a la unidad que sobrevive.
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      quantityMilli: 1000, unitIds: ['u0'],
      'assignment.units': { u0: { p1: true, p2: true } },
    }));
    // O dejar una unidad que ya no existe.
    await assertFails(updateDoc(doc(f, `${T}/lines/l1`), {
      quantityMilli: 1000, unitIds: ['u0'],
      'assignment.units': { u0: { p1: true }, u1: { p2: true } },
    }));
  });

  it('retira un producto entero con sus asignaciones', async () => {
    await assertSucceeds(deleteDoc(doc(db(ADMIN), `${T}/lines/l2`)));
  });

  // ── La frontera con el dinero ────────────────────────────────────────
  it('corregir el gasto NO da autoridad sobre los pagos', async () => {
    const f = db(ADMIN);
    // Confirmar el cobro de otro sigue siendo del receptor (P2.1/ADR-038).
    await assertFails(updateDoc(doc(f, `${SG}/settlements/st1`), {
      state: 'pending', stateHistory: [], updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(f, 'economicPayments/pay1'), {
      status: 'cancelled',
    }));
    await assertFails(deleteDoc(doc(f, 'economicPayments/pay1')));
    await assertFails(deleteDoc(doc(f, `${SG}/settlements/st1`)));
  });

  it('tampoco abre la sesión ni su shareCode', async () => {
    const f = db(ADMIN);
    await assertFails(updateDoc(doc(f, SG), { status: 'closed' }));
    await assertFails(deleteDoc(doc(f, T)));
    await assertFails(updateDoc(doc(f, `${SG}/participants/p2`), {
      claimedByDevice: ADMIN,
    }));
  });

  it('con la sesión cerrada no se corrige nada', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), SG), { status: 'closed' });
    });
    await assertFails(updateDoc(doc(db(ADMIN), T), cabecera()));
    await assertFails(updateDoc(doc(db(ADMIN), `${T}/lines/l1`), producto()));
    await assertFails(deleteDoc(doc(db(ADMIN), `${T}/lines/l2`)));
  });
});
