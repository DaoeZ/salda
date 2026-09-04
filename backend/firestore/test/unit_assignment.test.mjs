/**
 * A10: asignar el consumo de otra persona.
 *
 * Quien tiene autoridad sobre el gasto reparte directamente lo que ya sabe
 * —esto es de Alba, esto de Tete— sin esperar a que cada cual entre a
 * reclamarlo. Lo que fijan estas pruebas es la frontera: quién puede hacerlo,
 * sobre quién, con qué firma, y que repartir NO se convierta en poder editar
 * el contenido del ticket.
 *
 * Y una cosa más, que es criterio de aceptación: un rechazo tiene que ser un
 * rechazo. Antes de A10, denegar una escritura de línea agotaba el
 * presupuesto de 1000 expresiones de Rules y el error que llegaba era
 * «Unable to evaluate the expression», que no es lo mismo: es quedarse sin
 * gasolina a mitad de la comprobación.
 *
 * Ejecutar desde la raíz del repo:
 *   firebase emulators:exec --only firestore,storage --project demo-salda \
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
  deleteField,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

const ALBA = 'uid-alba'; // dueña de la sesión = creadora del gasto
const JEFA = 'uid-jefa'; // propietaria del grupo
const ADMIN = 'uid-admin'; // role: admin del grupo
const JORGE = 'uid-jorge'; // miembro normal, participante p2
const PAREJA = 'uid-pareja'; // la otra mitad de la relación, p2 en sr1
const AJENA = 'uid-ajena'; // administra OTRO grupo
const FUERA = 'uid-fuera'; // ni miembro ni nada
const INVITADA = 'uid-invitada'; // anónima con guestAccess, reclama p2

const G = 'sessions/sg1/accounts/a1/tickets/t1/lines/l1';
const R = 'sessions/sr1/accounts/a1/tickets/t1/lines/l1';

const db = (uid) =>
  env
    .authenticatedContext(
      uid,
      uid === INVITADA
        ? { firebase: { sign_in_provider: 'anonymous' } }
        : {
            email: `${uid}@salda.test`,
            email_verified: true,
            firebase: { sign_in_provider: 'password' },
          },
    )
    .firestore();

/** Una asignación tal y como la escribe la app: par (unidad, persona). */
const asignar = (
  actor,
  pid,
  { unit = 'u0', path = G, selected = true, firma } = {},
) => {
  const rubrica = firma === undefined ? actor : firma;
  // `firma: null` = escritura SIN procedencia, byte a byte la que manda el
  // cliente desde A3 cuando alguien se marca a sí mismo: el par se pone y la
  // firma se retira, porque marcarse uno mismo no tiene procedencia que
  // contar.
  return updateDoc(doc(db(actor), path), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.units.${unit}.${pid}`]: selected ? true : deleteField(),
    [`assignment.by.${unit}.${pid}`]:
      selected && rubrica !== null ? rubrica : deleteField(),
  });
};

/** Igual pero SIN firma: es lo que escribe hoy la web de invitados. */
const asignarSinFirma = (actor, pid, { unit = 'u0', path = G } = {}) =>
  updateDoc(doc(db(actor), path), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.units.${unit}.${pid}`]: true,
  });

/**
 * Deniega, y deniega DE VERDAD: no por quedarse sin presupuesto de
 * expresiones a mitad de la evaluación.
 */
async function assertDeniegaLimpio(promise) {
  await assert.rejects(promise, (error) => {
    const mensaje = `${error?.message ?? error}`;
    assert.ok(
      !mensaje.includes('maximum of'),
      `Rules se quedó sin presupuesto en vez de denegar: ${mensaje}`,
    );
    return true;
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-salda',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});
after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of [ALBA, JEFA, ADMIN, JORGE, PAREJA, AJENA, FUERA]) {
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
    // Relación: dos personas, sin jerarquía.
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

    for (const [sid, spaceId] of [['sg1', 'gr1'], ['sr1', 'rel1']]) {
      await setDoc(doc(f, `sessions/${sid}`), {
        ownerUid: ALBA, kind: 'single', name: 'Cena', status: 'open',
        splitModeDefault: 'byItem', shareCode: 'SECRET-CODE-16CHARS',
        currency: 'EUR', contextModelVersion: 1, spaceId,
        computeVersion: 0, totals: {}, balances: {},
      });
      await setDoc(doc(f, `sessions/${sid}/participants/p1`), {
        name: 'Alba', isOwner: true, order: 0, active: true,
        claimedByDevice: ALBA,
      });
      await setDoc(doc(f, `sessions/${sid}/participants/p2`), {
        name: 'Otro', isOwner: false, order: 1, active: true,
        claimedByDevice: sid === 'sg1' ? JORGE : PAREJA,
      });
      // Persona MANUAL: no tiene cuenta, no reclama nada y aun así consume.
      await setDoc(doc(f, `sessions/${sid}/participants/p3`), {
        name: 'Tete', isOwner: false, order: 2, active: true,
        claimedByDevice: '', manualId: 'm-tete',
      });
      // Invitada del enlace: sin cuenta social, reclama p5 desde la web.
      await setDoc(doc(f, `sessions/${sid}/participants/p5`), {
        name: 'Invitada', isOwner: false, order: 4, active: true,
        claimedByDevice: INVITADA,
      });
      await setDoc(doc(f, `sessions/${sid}/guestAccess/${INVITADA}`), {
        shareCode: 'SECRET-CODE-16CHARS',
      });
      // Alguien que ya no participa: no recibe consumo NUEVO.
      await setDoc(doc(f, `sessions/${sid}/participants/p4`), {
        name: 'Retirada', isOwner: false, order: 3, active: false,
        claimedByDevice: '',
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1`), { name: 'Cena' });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1`), {
        kind: 'manual', grandTotal: 1000, paidByParticipantId: 'p1',
        merchant: { name: 'Bar' }, spaceId, contextModelVersion: 1,
        splitModeOverride: 'byItem',
      });
      await setDoc(doc(f, `sessions/${sid}/accounts/a1/tickets/t1/lines/l1`), {
        name: 'Cocacola', totalPrice: 1000, quantityMilli: 2000, order: 0,
        unitIds: ['u0', 'u1'],
        assignment: { type: 'units', schemaVersion: 2, units: {} },
      });
    }
  });
});

describe('A10: quién reparte el consumo (grupo)', () => {
  it('la creadora del gasto asigna a sí misma, a otro y a un MANUAL',
    async () => {
      await assertSucceeds(asignar(ALBA, 'p1'));
      await assertSucceeds(asignar(ALBA, 'p2'));
      await assertSucceeds(asignar(ALBA, 'p3'));
    });

  it('la propietaria del grupo asigna en el gasto ajeno', async () => {
    await assertSucceeds(asignar(JEFA, 'p2'));
    await assertSucceeds(asignar(JEFA, 'p3'));
  });

  it('quien administra el grupo asigna en el gasto ajeno', async () => {
    await assertSucceeds(asignar(ADMIN, 'p2'));
    await assertSucceeds(asignar(ADMIN, 'p3'));
  });

  it('un miembro normal sigue eligiendo SOLO lo suyo', async () => {
    await assertSucceeds(asignar(JORGE, 'p2'));
    await assertDeniegaLimpio(asignar(JORGE, 'p1'));
    await assertDeniegaLimpio(asignar(JORGE, 'p3'));
  });

  it('quien administra OTRO grupo, o nadie, no toca nada', async () => {
    await assertDeniegaLimpio(asignar(AJENA, 'p2'));
    await assertDeniegaLimpio(asignar(FUERA, 'p2'));
  });

  it('un ex-miembro no recibe ni reparte', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`), { uid: JORGE }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const { deleteDoc } = await import('firebase/firestore');
      await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
    });
    await assertDeniegaLimpio(asignar(JORGE, 'p2'));
  });
});

// ── La autoridad del creador no es una puerta trasera ──────────────────
// El dueño de la sesión podía repartir desde antes de A10, y eso no se le
// quita. Lo que se le quita es la rama que no validaba forma: con ella, un
// cliente modificado suyo podía dejar «u0 → Jorge» sin decir quién lo puso.
// No falsificaba a nadie —el UID lo pone el servidor—, pero borraba la
// procedencia, que es justo lo que A10 prometía conservar.
describe('A10: el creador reparte, pero con procedencia', () => {
  it('se asigna a sí misma', () => assertSucceeds(asignar(ALBA, 'p1')));

  it('asigna a un tercero firmando con su propio UID', async () => {
    await assertSucceeds(asignar(ALBA, 'p2'));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.equal(guardado.assignment.by.u0.p2, ALBA);
  });

  it('NO puede asignar a un tercero sin firma', () =>
    assertDeniegaLimpio(asignarSinFirma(ALBA, 'p2')));

  it('NO puede asignar a un MANUAL sin firma', () =>
    assertDeniegaLimpio(asignarSinFirma(ALBA, 'p3')));

  it('NO puede atribuir la asignación a otra persona', () =>
    assertDeniegaLimpio(asignar(ALBA, 'p2', { firma: JORGE })));

  it('retira la asignación de un tercero llevándose su firma', async () => {
    await assertSucceeds(asignar(ALBA, 'p2'));
    await assertSucceeds(asignar(ALBA, 'p2', { selected: false }));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.deepEqual(guardado.assignment.units.u0, {});
    assert.deepEqual(guardado.assignment.by.u0, {});
  });

  it('no retira una asignación dejando la firma huérfana', () =>
    assertDeniegaLimpio(updateDoc(doc(db(ALBA), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': deleteField(),
      'assignment.by.u0.p2': ALBA,
    })));

  it('tampoco reparte de más en una sola escritura', () =>
    assertDeniegaLimpio(updateDoc(doc(db(ALBA), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
      'assignment.units.u1.p3': true,
      'assignment.by.u0.p2': ALBA,
      'assignment.by.u1.p3': ALBA,
    })));

  // La otra mitad del mismo agujero: si repartir sin firma se deniega pero
  // «corregir el contenido» acepta cualquier assignment, la puerta sigue
  // abierta, solo que con un nombre distinto en la misma escritura.
  it('no cuela una asignación junto al dato fuente de la línea', async () => {
    for (const extra of [{ name: 'Otra cosa' }, { totalPrice: 1 },
      { quantityMilli: 5000 }, { unitIds: ['u0', 'u1', 'u2'] }]) {
      await assertDeniegaLimpio(updateDoc(doc(db(ALBA), G), {
        ...extra,
        'assignment.units.u0.p2': true,
      }));
    }
  });

  it('pero sigue corrigiendo el contenido y podando unidades', async () => {
    await assertSucceeds(updateDoc(doc(db(ALBA), G), { name: 'Fanta' }));
    await assertSucceeds(asignar(ALBA, 'p2', { unit: 'u1' }));
    await assertSucceeds(updateDoc(doc(db(ALBA), G), {
      quantityMilli: 1000,
      unitIds: ['u0'],
      'assignment.units.u1': deleteField(),
      'assignment.by.u1': deleteField(),
    }));
  });

  it('y el reparto histórico por pesos no cambia para nadie', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), 'sessions/sg1/accounts/a1/tickets/t1/lines/l2'),
      {
        name: 'Tapa', totalPrice: 400, quantityMilli: 1000, order: 1,
        assignment: { type: 'unassigned', participants: {} },
      }));
    const L2 = 'sessions/sg1/accounts/a1/tickets/t1/lines/l2';
    await assertSucceeds(updateDoc(doc(db(ALBA), L2), {
      'assignment.type': 'one',
      'assignment.lastEditorPid': 'p2',
      'assignment.participants.p2': 1,
    }));
  });
});

describe('A10: sobre quién se puede asignar', () => {
  it('un participante que ya no está activo no recibe consumo nuevo', () =>
    assertDeniegaLimpio(asignar(ADMIN, 'p4')));

  it('un pid inventado tampoco', () =>
    assertDeniegaLimpio(asignar(ADMIN, 'p9')));

  it('ni una unidad que no existe', () =>
    assertDeniegaLimpio(asignar(ADMIN, 'p2', { unit: 'u7' })));

  // A4: tampoco uno mismo. `recompute` reparte sobre los ACTIVOS, así que la
  // autoselección de alguien desactivado acababa recayendo en el pagador
  // mientras la pantalla lo pintaba consumiendo: dos versiones del gasto.
  it('un participante desactivado NO puede autoseleccionarse', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'sessions/sg1/participants/p2'), {
        active: false,
      });
    });
    await assertDeniegaLimpio(asignarSinFirma(JORGE, 'p2'));
  });
});

describe('A10: compartir, retirar y reasignar', () => {
  it('dos personas comparten la MISMA unidad', async () => {
    await assertSucceeds(asignar(ADMIN, 'p2'));
    await assertSucceeds(asignar(ADMIN, 'p3'));
    const guardado = await getDoc(doc(db(ALBA), G));
    assert.deepEqual(guardado.data().assignment.units.u0, {
      p2: true, p3: true,
    });
  });

  it('cada unidad va a una persona distinta', async () => {
    await assertSucceeds(asignar(ADMIN, 'p2', { unit: 'u0' }));
    await assertSucceeds(asignar(ADMIN, 'p3', { unit: 'u1' }));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.deepEqual(guardado.assignment.units.u0, { p2: true });
    assert.deepEqual(guardado.assignment.units.u1, { p3: true });
  });

  it('quien reparte también retira, y la firma se va con la asignación',
    async () => {
      await assertSucceeds(asignar(ADMIN, 'p2'));
      await assertSucceeds(asignar(ADMIN, 'p2', { selected: false }));
      const guardado = (await getDoc(doc(db(ALBA), G))).data();
      assert.deepEqual(guardado.assignment.units.u0, {});
      assert.deepEqual(guardado.assignment.by.u0, {});
    });

  it('un miembro normal NO retira el consumo de otro', async () => {
    await assertSucceeds(asignar(ADMIN, 'p1'));
    await assertDeniegaLimpio(asignar(JORGE, 'p1', { selected: false }));
  });

  it('una escritura toca una sola unidad y una sola persona', () =>
    assertDeniegaLimpio(updateDoc(doc(db(ADMIN), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
      'assignment.units.u1.p3': true, // de propina, en otra unidad
      'assignment.by.u0.p2': ADMIN,
      'assignment.by.u1.p3': ADMIN,
    })));
});

describe('A10: la firma no se puede falsear', () => {
  it('no se puede atribuir la asignación a otra persona', () =>
    assertDeniegaLimpio(asignar(ADMIN, 'p2', { firma: ALBA })));

  it('quien administra no puede asignar a un tercero SIN firmar', () =>
    assertDeniegaLimpio(asignarSinFirma(ADMIN, 'p2')));

  it('elegir lo propio sin firma sigue valiendo (la web no la escribe)',
    () => assertSucceeds(asignarSinFirma(JORGE, 'p2')));

  it('y si la firma, tiene que ser la suya', () =>
    assertDeniegaLimpio(asignar(JORGE, 'p2', { firma: ALBA })));

  // A2/A3: la denegación espuria que el cliente se provocaba solo. Cuando
  // firmaba TODA selección, volver a marcar una casilla que ya estaba
  // marcada —una pantalla un instante desfasada basta— intentaba estampar
  // una firma sobre una asignación viva, y Rules lo rechazaba con razón: la
  // app enseñaba un error por una escritura que no cambiaba nada. Sin firma
  // la escritura es idempotente y pasa.
  it('volver a marcar lo tuyo, ya marcado, no choca con ninguna firma',
    async () => {
      await assertSucceeds(asignar(JORGE, 'p2', { firma: null }));
      await assertSucceeds(asignar(JORGE, 'p2', { firma: null }));
      const guardado = (await getDoc(doc(db(ALBA), G))).data();
      assert.equal(guardado.assignment.units.u0.p2, true);
      // Y sigue siendo lo que es: una autoselección, sin procedencia.
      assert.equal(guardado.assignment.by?.u0?.p2, undefined);
    });

  // Lo que A3 NO arregla, y conviene tener escrito: quien administra sigue
  // sin poder tocar una casilla que su dueño ya se marcó. La asignación
  // existe y su procedencia —vacía: es una autoselección— no se reescribe,
  // así que firmar la deniega, y no firmar también, porque asignar por otra
  // persona exige firma. Es una limitación de Rules, no del cliente; lo que
  // se fija aquí es que la denegación sea LIMPIA y no un presupuesto agotado.
  it('la admin todavía no puede marcar lo que su dueño autoseleccionó',
    async () => {
      await assertSucceeds(asignar(JORGE, 'p2', { firma: null }));
      await assertDeniegaLimpio(asignar(JEFA, 'p2'));
      await assertDeniegaLimpio(asignar(JEFA, 'p2', { firma: null }));
    });

  it('la firma de una asignación NO se pierde al tocar otra unidad',
    async () => {
      await assertSucceeds(asignar(ADMIN, 'p2', { unit: 'u0' }));
      await assertSucceeds(asignar(JORGE, 'p2', { unit: 'u1' }));
      const guardado = (await getDoc(doc(db(ALBA), G))).data();
      assert.equal(guardado.assignment.by.u0.p2, ADMIN);
      assert.equal(guardado.assignment.by.u1.p2, JORGE);
    });
});

describe('A10: repartir NO es editar el gasto', () => {
  const conContenido = (actor, extra) =>
    updateDoc(doc(db(actor), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.u0.p2': true,
      'assignment.by.u0.p2': actor,
      ...extra,
    });

  it('no se cuela un nombre', () =>
    assertDeniegaLimpio(conContenido(ADMIN, { name: 'Otra cosa' })));

  it('no se cuela un precio', () =>
    assertDeniegaLimpio(conContenido(ADMIN, { totalPrice: 1 })));

  it('no se cuela una cantidad', () =>
    assertDeniegaLimpio(conContenido(ADMIN, { quantityMilli: 5000 })));

  it('no se cuelan unidades nuevas', () =>
    assertDeniegaLimpio(conContenido(ADMIN, { unitIds: ['u0', 'u1', 'u2'] })));
});

// ── Soltar lo que te asignó otra persona ────────────────────────────────
// El caso que A10 dejó roto: si un administrador te asigna una unidad, esa
// asignación viene FIRMADA. Al desmarcarte hay que retirar también la firma
// —una procedencia sin asignación detrás no explica nada—, y la web de
// invitados no lo hacía: borraba `units` y dejaba `by`, así que Rules
// rechazaba la escritura entera y quedabas atrapado en un consumo ajeno.
describe('A10: retirar el consumo que te asignaron', () => {
  it('la invitada suelta lo que le asignó el administrador', async () => {
    await assertSucceeds(asignar(ADMIN, 'p5'));
    await assertSucceeds(asignar(INVITADA, 'p5', { selected: false }));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.deepEqual(guardado.assignment.units.u0, {});
    assert.deepEqual(guardado.assignment.by.u0, {});
  });

  it('y no se lleva por delante a quien comparte la unidad', async () => {
    await assertSucceeds(asignar(ADMIN, 'p5'));
    await assertSucceeds(asignar(ADMIN, 'p3'));
    await assertSucceeds(asignar(INVITADA, 'p5', { selected: false }));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.deepEqual(guardado.assignment.units.u0, { p3: true });
    assert.deepEqual(guardado.assignment.by.u0, { p3: ADMIN });
  });

  it('pero no suelta el consumo de OTRA persona', async () => {
    await assertSucceeds(asignar(ADMIN, 'p3'));
    await assertDeniegaLimpio(asignar(INVITADA, 'p3', { selected: false }));
  });

  it('ni borra procedencia ajena dejando la asignación en pie', async () => {
    await assertSucceeds(asignar(ADMIN, 'p5'));
    await assertDeniegaLimpio(updateDoc(doc(db(INVITADA), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': 'p5',
      'assignment.lastEditedUnit': 'u0',
      'assignment.by.u0.p5': deleteField(),
    }));
  });

  // Mientras la asignación existe conserva su procedencia: reescribirla
  // convertiría «me lo asignó el administrador» en «me lo puse yo».
  it('ni se apropia de la firma de una asignación viva', async () => {
    await assertSucceeds(asignar(ADMIN, 'p5'));
    await assertDeniegaLimpio(asignar(INVITADA, 'p5', { firma: INVITADA }));
    await assertDeniegaLimpio(asignar(INVITADA, 'p5', { firma: ALBA }));
    const guardado = (await getDoc(doc(db(ALBA), G))).data();
    assert.equal(guardado.assignment.by.u0.p5, ADMIN);
  });

  it('y sigue eligiendo lo suyo sin firmar, como siempre', async () => {
    await assertSucceeds(asignarSinFirma(INVITADA, 'p5'));
    await assertDeniegaLimpio(asignarSinFirma(INVITADA, 'p2'));
  });
});

describe('A10: relaciones', () => {
  it('la creadora reparte entre las dos, y con un manual', async () => {
    await assertSucceeds(asignar(ALBA, 'p1', { path: R }));
    await assertSucceeds(asignar(ALBA, 'p2', { path: R }));
    await assertSucceeds(asignar(ALBA, 'p3', { path: R }));
  });

  it('la contraparte elige LO SUYO desde la app, sin enlace de invitado', () =>
    assertSucceeds(asignar(PAREJA, 'p2', { path: R })));

  it('y también puede leer el gasto que comparte', async () => {
    await assertSucceeds(getDoc(doc(db(PAREJA), R)));
    await assertSucceeds(
      getDoc(doc(db(PAREJA), 'sessions/sr1/accounts/a1/tickets/t1')));
    await assertSucceeds(
      getDoc(doc(db(PAREJA), 'sessions/sr1/participants/p1')));
  });

  it('pero no asigna el consumo de la otra persona', () =>
    assertDeniegaLimpio(asignar(PAREJA, 'p1', { path: R })));

  it('ni el de un manual: una relación no tiene administración', () =>
    assertDeniegaLimpio(asignar(PAREJA, 'p3', { path: R })));

  it('y sigue sin poder corregir el contenido', () =>
    assertDeniegaLimpio(updateDoc(doc(db(PAREJA), R), { name: 'Otra cosa' })));

  it('quien administra OTRO grupo no entra en la relación', () =>
    assertDeniegaLimpio(asignar(JEFA, 'p2', { path: R })));
});

describe('A10: fronteras de siempre', () => {
  it('con la sesión CERRADA no reparte nadie', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), 'sessions/sg1'), { status: 'closed' }));
    await assertDeniegaLimpio(asignar(ALBA, 'p2'));
    await assertDeniegaLimpio(asignar(ADMIN, 'p2'));
    await assertDeniegaLimpio(asignar(JORGE, 'p2'));
  });

  it('a partes iguales no hay nada que repartir por producto', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), 'sessions/sg1/accounts/a1/tickets/t1'),
      { splitModeOverride: 'equal' }));
    await assertDeniegaLimpio(asignar(ADMIN, 'p2'));
    await assertDeniegaLimpio(asignar(JORGE, 'p2'));
  });
});
