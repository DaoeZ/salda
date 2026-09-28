/**
 * A19 — cierre de consumo: quién puede terminar, quién puede reabrir, y por
 * qué es IMPOSIBLE dejar un «he terminado» obsoleto.
 *
 * El invariante que fijan estas pruebas: en un ticket bajo el protocolo,
 * ninguna escritura de reparto pasa si el pid afectado no queda abierto tras
 * el commit. Y una regresión de presupuesto: el camino de A10 sobre un
 * MANUAL es el que agotaba las 1000 expresiones cuando la comprobación
 * costaba DOS accesos al ticket; con uno cabe.
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
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

const ALBA = 'uid-alba'; // dueña de la sesión
const JEFA = 'uid-jefa'; // propietaria del grupo (autoridad A10)
const JORGE = 'uid-jorge'; // miembro normal, participante p2
const EDGAR = 'uid-edgar'; // miembro normal, participante p6
const INVITADA = 'uid-invitada'; // anónima con guestAccess, reclama p5

const T = 'sessions/sg1/accounts/a1/tickets/t1';
const L = `${T}/lines/l1`;
const UNIDADES = 6;

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

/** Elegir consumo: línea + reapertura del pid, en UN batch de dos docs. */
const elegir = (
  actor,
  pid,
  { unit = 'u0', selected = true, firma, reabre = true } = {},
) => {
  const f = db(actor);
  const b = writeBatch(f);
  b.update(doc(f, L), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.units.${unit}.${pid}`]: selected ? true : deleteField(),
    [`assignment.by.${unit}.${pid}`]:
      selected && firma ? firma : deleteField(),
  });
  if (reabre) {
    b.update(doc(f, T), {
      'picking.lastTarget': pid,
      [`picking.open.${pid}`]: true,
    });
  }
  return b.commit();
};

/** «He terminado»: el pid sale del mapa de pendientes. */
const terminar = (actor, pid) =>
  updateDoc(doc(db(actor), T), {
    'picking.lastTarget': pid,
    [`picking.open.${pid}`]: deleteField(),
  });

/** Deniega, y deniega DE VERDAD: no por quedarse sin presupuesto. */
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

/** `protocolo: false` siembra un ticket anterior a A19. */
async function sembrar({ protocolo = true, unidades = UNIDADES } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of [ALBA, JEFA, JORGE, EDGAR]) {
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
    for (const uid of [JEFA, ALBA, JORGE, EDGAR]) {
      await setDoc(doc(f, `spaces/gr1/members/${uid}`), {
        uid, joinedAt: serverTimestamp(),
      });
    }
    await setDoc(doc(f, 'sessions/sg1'), {
      ownerUid: ALBA, kind: 'single', name: 'Cena', status: 'open',
      splitModeDefault: 'byItem', shareCode: 'SECRET-CODE-16CHARS',
      currency: 'EUR', contextModelVersion: 1, spaceId: 'gr1',
      computeVersion: 0, totals: {}, balances: {},
    });
    await setDoc(doc(f, 'sessions/sg1/participants/p1'), {
      name: 'Alba', isOwner: true, order: 0, active: true, claimedByDevice: ALBA,
    });
    await setDoc(doc(f, 'sessions/sg1/participants/p2'), {
      name: 'Jorge', isOwner: false, order: 1, active: true,
      claimedByDevice: JORGE,
    });
    // Persona MANUAL: no reclama nada y aun así consume. Solo A10 la cierra.
    await setDoc(doc(f, 'sessions/sg1/participants/p3'), {
      name: 'Tete', isOwner: false, order: 2, active: true,
      claimedByDevice: '', manualId: 'm-tete',
    });
    await setDoc(doc(f, 'sessions/sg1/participants/p5'), {
      name: 'Invitada', isOwner: false, order: 4, active: true,
      claimedByDevice: INVITADA,
    });
    await setDoc(doc(f, 'sessions/sg1/participants/p6'), {
      name: 'Edgar', isOwner: false, order: 5, active: true,
      claimedByDevice: EDGAR,
    });
    await setDoc(doc(f, `sessions/sg1/guestAccess/${INVITADA}`), {
      shareCode: 'SECRET-CODE-16CHARS',
    });
    await setDoc(doc(f, 'sessions/sg1/accounts/a1'), { name: 'Cena' });
    await setDoc(doc(f, T), {
      kind: 'manual', grandTotal: 6000, paidByParticipantId: 'p1',
      merchant: { name: 'Bar' }, spaceId: 'gr1', contextModelVersion: 1,
      splitModeOverride: 'byItem',
      ...(protocolo
        ? {
            pickingModelVersion: 1,
            picking: {
              open: { p1: true, p2: true, p3: true, p5: true, p6: true },
            },
          }
        : {}),
    });
    await setDoc(doc(f, L), {
      name: 'Cerveza', totalPrice: 6000, quantityMilli: unidades * 1000,
      order: 0,
      unitIds: Array.from({ length: unidades }, (_, i) => `u${i}`),
      assignment: { type: 'units', schemaVersion: 2, units: {} },
    });
  });
}

describe('A19: elegir con el protocolo activo', () => {
  beforeEach(() => sembrar());

  it('un participante activo elige lo suyo', () =>
    assertSucceeds(elegir(JORGE, 'p2')));

  it('la autoselección NO lleva firma de tercero', () =>
    assertSucceeds(elegir(JORGE, 'p2', { firma: undefined })));

  it('A10 asigna a otra persona CON procedencia', () =>
    assertSucceeds(elegir(JEFA, 'p2', { firma: JEFA })));

  it('A10 sin firma sobre un tercero queda denegado', () =>
    assertDeniegaLimpio(elegir(JEFA, 'p3', { firma: undefined })));

  it('un participante DESACTIVADO no elige', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'sessions/sg1/participants/p2'), {
        active: false,
      });
    });
    await assertDeniegaLimpio(elegir(JORGE, 'p2'));
  });

  it('un ex-miembro del grupo no elige', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const { deleteDoc } = await import('firebase/firestore');
      await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
    });
    await assertDeniegaLimpio(elegir(JORGE, 'p2'));
  });

  it('con la sesión cerrada no elige nadie', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'sessions/sg1'), {
        status: 'closed',
      });
    });
    await assertDeniegaLimpio(elegir(JORGE, 'p2'));
  });

  it('la invitada web sigue exactamente el mismo protocolo', async () => {
    await assertSucceeds(elegir(INVITADA, 'p5', { unit: 'u3' }));
    await assertSucceeds(terminar(INVITADA, 'p5'));
    await assertDeniegaLimpio(
      elegir(INVITADA, 'p5', { unit: 'u4', reabre: false }),
    );
  });
});

describe('A19: la reapertura es obligatoria y atómica', () => {
  beforeEach(() => sembrar());

  it('quien ya terminó NO puede cambiar sin reabrirse', async () => {
    await terminar(JORGE, 'p2');
    await assertDeniegaLimpio(
      elegir(JORGE, 'p2', { unit: 'u1', reabre: false }),
    );
  });

  it('cambio y reapertura juntos, en el mismo commit, se permiten', async () => {
    await terminar(JORGE, 'p2');
    await assertSucceeds(elegir(JORGE, 'p2', { unit: 'u1' }));
  });

  it('A10 cambia el consumo de un MANUAL y lo reabre en el mismo commit',
    async () => {
      await terminar(JEFA, 'p3');
      await assertDeniegaLimpio(
        elegir(JEFA, 'p3', { unit: 'u2', firma: JEFA, reabre: false }),
      );
      // REGRESIÓN DE PRESUPUESTO: este es el camino que agotaba las 1000
      // expresiones cuando la comprobación costaba dos accesos al ticket.
      await assertSucceeds(elegir(JEFA, 'p3', { unit: 'u2', firma: JEFA }));
    });

  it('reabrir a OTRA persona sin autoridad queda denegado', async () => {
    await terminar(JORGE, 'p2');
    // Edgar intenta reabrir a Jorge para tocarle el consumo.
    await assertDeniegaLimpio(elegir(EDGAR, 'p2', { firma: EDGAR }));
  });
});

describe('A19: terminar', () => {
  beforeEach(() => sembrar());

  it('cada cual cierra SU pid', () => assertSucceeds(terminar(JORGE, 'p2')));

  it('A10 cierra el pid de otra persona y el de un manual', async () => {
    await assertSucceeds(terminar(JEFA, 'p2'));
    await assertSucceeds(terminar(ALBA, 'p3'));
  });

  it('un participante normal NO cierra el pid de otra persona', () =>
    assertDeniegaLimpio(terminar(JORGE, 'p1')));

  it('la invitada cierra el suyo y no el ajeno', async () => {
    await assertSucceeds(terminar(INVITADA, 'p5'));
    await assertDeniegaLimpio(terminar(INVITADA, 'p6'));
  });

  it('nadie toca la huella de topología', () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p1',
        'picking.fingerprint': 'inventada',
      }),
    ));

  it('nadie toca la economía congelada, ni siquiera el dueño', () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p1',
        'picking.firmContribution': {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      }),
    ));

  it('una escritura de picking no cuela otro campo del ticket', () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p2',
        'picking.open.p2': deleteField(),
        grandTotal: 1,
      }),
    ));

  it('no se cierran DOS personas en la misma escritura', () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p2',
        'picking.open.p2': deleteField(),
        'picking.open.p6': deleteField(),
      }),
    ));

  it('terminar sigue permitido con la economía ya congelada', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), T), {
        'picking.firmContribution': {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      });
    });
    await assertSucceeds(terminar(JORGE, 'p2'));
  });
});

describe('A19: compatibilidad y presupuesto', () => {
  it('un ticket SIN pickingModelVersion se comporta como hoy', async () => {
    await sembrar({ protocolo: false });
    await assertSucceeds(elegir(JORGE, 'p2', { reabre: false }));
  });

  it('cliente antiguo con el pid abierto sigue pudiendo editar', async () => {
    await sembrar();
    await assertSucceeds(elegir(JORGE, 'p2', { reabre: false }));
  });

  it('cliente antiguo con el pid cerrado queda denegado', async () => {
    await sembrar();
    await terminar(JORGE, 'p2');
    await assertDeniegaLimpio(
      elegir(JORGE, 'p2', { unit: 'u2', reabre: false }),
    );
  });

  it('el dueño crea el ticket con el protocolo ya sembrado', async () => {
    await sembrar();
    await assertSucceeds(
      setDoc(doc(db(ALBA), 'sessions/sg1/accounts/a1/tickets/t9'), {
        kind: 'manual', grandTotal: 1000, paidByParticipantId: 'p1',
        merchant: { name: 'Bar' }, spaceId: 'gr1', contextModelVersion: 1,
        splitModeOverride: 'byItem',
        pickingModelVersion: 1,
        picking: { open: { p1: true, p2: true } },
      }),
    );
  });

  it('el dueño NO puede vaciar `open` por la puerta de siempre', async () => {
    await sembrar();
    await assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        grandTotal: 6000,
        paidByParticipantId: 'p1',
        picking: { open: {} },
      }),
    );
  });

  it('presupuesto: 24 unidades seguidas con la comprobación extra',
    async () => {
      await sembrar({ unidades: 24 });
      for (let u = 0; u < 24; u++) {
        await assertSucceeds(elegir(JORGE, 'p2', { unit: `u${u}` }));
      }
    });
});
