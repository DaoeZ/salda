/**
 * A11d: expulsión administrativa, evidencia por ciclo y reentrada.
 *
 * Dos documentos con dos vidas distintas, y el ADR-039 explica por qué NO
 * pueden ser uno solo:
 *
 *  - `spaces/{id}/removals/{uid}_{joinedAtMillis}`: evidencia HISTÓRICA,
 *    append-only. P6 la consulta cuando le llega el evento de borrado —tarde,
 *    reintentado, o cuando la persona ya va por otro ciclo— así que no puede
 *    poder cambiar de significado.
 *  - `spaces/{id}/entryBlocks/{uid}`: bloqueo VIGENTE del enlace general.
 *    Nace con la expulsión y muere con la readmisión explícita.
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

const JEFA = 'uid-jefa'; // propietaria de gr1
const ADMIN = 'uid-admin'; // role: admin en gr1
const ADMIN2 = 'uid-admin2'; // otro admin: un admin no toca a otro admin
const JORGE = 'uid-jorge'; // miembro normal
const AJENA = 'uid-ajena'; // administra OTRO grupo
const PAREJA = 'uid-pareja'; // la otra mitad de la relación rel1

// joinedAt fijos: la identidad del ciclo se deriva de ellos.
const CICLO_A = Timestamp.fromMillis(2_000_000);
const CICLO_B = Timestamp.fromMillis(9_000_000);
const cicloId = (uid, joinedAt) => `${uid}_${joinedAt.toMillis()}`;

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

/** Estado base: gr1 con propietaria, dos admins y Jorge en el ciclo A. */
async function sembrar({ jorgeJoinedAt = CICLO_A, jorgeEsMiembro = true } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of [JEFA, ADMIN, ADMIN2, JORGE, AJENA, PAREJA]) {
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
    await setDoc(doc(f, `spaces/gr1/members/${JEFA}`), {
      uid: JEFA, joinedAt: Timestamp.fromMillis(1_000_000),
    });
    for (const uid of [ADMIN, ADMIN2]) {
      await setDoc(doc(f, `spaces/gr1/members/${uid}`), {
        uid, joinedAt: Timestamp.fromMillis(1_000_000), role: 'admin',
      });
    }
    if (jorgeEsMiembro) {
      await setDoc(doc(f, `spaces/gr1/members/${JORGE}`), {
        uid: JORGE, joinedAt: jorgeJoinedAt,
      });
    }
    // Enlace general vivo del grupo.
    await setDoc(doc(f, 'spaceLinks/tok1'), {
      spaceId: 'gr1', spaceName: 'Piso', createdByUid: JEFA, status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 1,
    });
    // Otro grupo: su administradora no manda aquí.
    await setDoc(doc(f, 'spaces/gr2'), {
      name: 'Otro', ownerUid: AJENA, kind: 'group', status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    await setDoc(doc(f, `spaces/gr2/members/${AJENA}`), {
      uid: AJENA, joinedAt: serverTimestamp(),
    });
    // Relación: NO tiene expulsión administrativa.
    await setDoc(doc(f, 'spaces/rel1'), {
      name: 'Jefa y pareja', ownerUid: JEFA, kind: 'relationship',
      relationshipUids: [JEFA, PAREJA].sort(), status: 'active',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      schemaVersion: 2,
    });
    for (const uid of [JEFA, PAREJA]) {
      await setDoc(doc(f, `spaces/rel1/members/${uid}`), {
        uid, joinedAt: Timestamp.fromMillis(1_000_000),
      });
    }
  });
}

/** La expulsión REAL: tres escrituras y un solo commit. */
const expulsar = (actor, objetivo, joinedAt, { spaceId = 'gr1' } = {}) => {
  const f = db(actor);
  const batch = writeBatch(f);
  batch.set(doc(f, `spaces/${spaceId}/removals/${cicloId(objetivo, joinedAt)}`), {
    uid: objetivo, membershipJoinedAt: joinedAt, removedBy: actor,
    removedAt: serverTimestamp(), schemaVersion: 1,
  });
  batch.set(doc(f, `spaces/${spaceId}/entryBlocks/${objetivo}`), {
    uid: objetivo, membershipJoinedAt: joinedAt,
    blockedAt: serverTimestamp(), schemaVersion: 1,
  });
  batch.delete(doc(f, `spaces/${spaceId}/members/${objetivo}`));
  return batch.commit();
};

/** Entrar por el ENLACE general: prueba de conocimiento + membresía. */
const entrarPorEnlace = (uid) => {
  const f = db(uid);
  const batch = writeBatch(f);
  batch.set(doc(f, `spaces/gr1/joinGrants/${uid}`), {
    uid, token: 'tok1', createdAt: serverTimestamp(),
  });
  batch.set(doc(f, `spaces/gr1/members/${uid}`), {
    uid, joinedAt: serverTimestamp(),
  });
  return batch.commit();
};

/** Aceptar la invitación: resuelve, entra y levanta el bloqueo si lo hay. */
const aceptarInvitacion = (uid, { levantarBloqueo = true } = {}) => {
  const f = db(uid);
  const batch = writeBatch(f);
  batch.update(doc(f, `spaceInvites/gr1_${uid}`), {
    status: 'accepted', updatedAt: serverTimestamp(),
  });
  batch.set(doc(f, `spaces/gr1/members/${uid}`), {
    uid, joinedAt: serverTimestamp(),
  });
  if (levantarBloqueo) {
    batch.delete(doc(f, `spaces/gr1/entryBlocks/${uid}`));
  }
  return batch.commit();
};

const invitar = (uid) => setDoc(doc(db(JEFA), `spaceInvites/gr1_${uid}`), {
  spaceId: 'gr1', spaceName: 'Piso', fromUid: JEFA, toUid: uid,
  status: 'pending', createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

describe('A11d: autoridad de expulsión', () => {
  beforeEach(() => sembrar());

  it('el propietario expulsa a un miembro normal', () =>
    assertSucceeds(expulsar(JEFA, JORGE, CICLO_A)));

  it('el propietario expulsa a un administrador', () =>
    assertSucceeds(
      expulsar(JEFA, ADMIN, Timestamp.fromMillis(1_000_000))));

  it('un administrador expulsa a un miembro normal', () =>
    assertSucceeds(expulsar(ADMIN, JORGE, CICLO_A)));

  it('un administrador NO expulsa a otro administrador', () =>
    assertFails(
      expulsar(ADMIN, ADMIN2, Timestamp.fromMillis(1_000_000))));

  it('un administrador NO expulsa al propietario', () =>
    assertFails(expulsar(ADMIN, JEFA, Timestamp.fromMillis(1_000_000))));

  it('un miembro normal no expulsa a nadie', () =>
    assertFails(expulsar(JORGE, ADMIN, Timestamp.fromMillis(1_000_000))));

  it('quien administra OTRO grupo no expulsa aquí', () =>
    assertFails(expulsar(AJENA, JORGE, CICLO_A)));

  it('nadie se expulsa a sí mismo con autoridad administrativa', () =>
    assertFails(expulsar(ADMIN, ADMIN, Timestamp.fromMillis(1_000_000))));

  // El agujero preexistente que A11d cierra: una relación tiene `ownerUid`,
  // pero no jerarquía. Retirar a la otra mitad dejaría un contexto de una
  // sola identidad.
  it('una RELACIÓN no tiene expulsión administrativa', async () => {
    await assertFails(
      expulsar(JEFA, PAREJA, Timestamp.fromMillis(1_000_000),
        { spaceId: 'rel1' }));
    // Y el borrado suelto tampoco: la única baja sigue siendo salir uno mismo.
    await assertFails(
      deleteDoc(doc(db(JEFA), `spaces/rel1/members/${PAREJA}`)));
    await assertSucceeds(
      deleteDoc(doc(db(PAREJA), `spaces/rel1/members/${PAREJA}`)));
  });

  it('salir voluntariamente sigue sin evidencia ni bloqueo', async () => {
    await assertSucceeds(
      deleteDoc(doc(db(JORGE), `spaces/gr1/members/${JORGE}`)));
    const bloqueo = await getDoc(
      doc(db(JEFA), `spaces/gr1/entryBlocks/${JORGE}`));
    if (bloqueo.exists()) throw new Error('una salida dejó bloqueo');
  });
});

describe('A11d: la expulsión es todo o nada', () => {
  beforeEach(() => sembrar());

  it('borrar la membresía sin evidencia ni bloqueo: denegado', () =>
    assertFails(deleteDoc(doc(db(JEFA), `spaces/gr1/members/${JORGE}`))));

  it('evidencia sin expulsar: denegada', () =>
    assertFails(setDoc(
      doc(db(JEFA), `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`), {
        uid: JORGE, membershipJoinedAt: CICLO_A, removedBy: JEFA,
        removedAt: serverTimestamp(), schemaVersion: 1,
      })));

  it('bloqueo sin evidencia: denegado', async () => {
    const f = db(JEFA);
    const batch = writeBatch(f);
    batch.set(doc(f, `spaces/gr1/entryBlocks/${JORGE}`), {
      uid: JORGE, membershipJoinedAt: CICLO_A,
      blockedAt: serverTimestamp(), schemaVersion: 1,
    });
    batch.delete(doc(f, `spaces/gr1/members/${JORGE}`));
    await assertFails(batch.commit());
  });

  it('evidencia con un joinedAt que no es el del ciclo: denegada', () =>
    assertFails(expulsar(JEFA, JORGE, CICLO_B)));

  it('veto preventivo a quien nunca fue miembro: denegado', async () => {
    await sembrar({ jorgeEsMiembro: false });
    await assertFails(expulsar(JEFA, JORGE, CICLO_A));
  });

  it('la evidencia es inmutable: ni update ni delete', async () => {
    await assertSucceeds(expulsar(JEFA, JORGE, CICLO_A));
    const ruta = `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`;
    await assertFails(updateDoc(doc(db(JEFA), ruta), { removedBy: ADMIN }));
    await assertFails(deleteDoc(doc(db(JEFA), ruta)));
  });

  it('el expulsado no puede fabricarse su propia evidencia', () =>
    assertFails(expulsar(JORGE, JORGE, CICLO_A)));
});

describe('A11d: bloqueo del enlace y readmisión', () => {
  beforeEach(async () => {
    await sembrar();
    await assertSucceeds(expulsar(JEFA, JORGE, CICLO_A));
  });

  it('con el bloqueo vigente el enlace general no readmite', () =>
    assertFails(entrarPorEnlace(JORGE)));

  it('una invitación ANTERIOR a la expulsión no readmite', async () => {
    // Se fabrica con Admin: por Rules ya no puede nacer con fecha inventada.
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `spaceInvites/gr1_${JORGE}`), {
        spaceId: 'gr1', spaceName: 'Piso', fromUid: JEFA, toUid: JORGE,
        status: 'pending', createdAt: Timestamp.fromMillis(1_500_000),
        updatedAt: Timestamp.fromMillis(1_500_000),
      }));
    await assertFails(aceptarInvitacion(JORGE));
  });

  it('el expulsado no se readmite renovando él la invitación', async () => {
    // Una `accepted` vieja (la que le dio entrada en su día) sigue ahí. Solo
    // el propietario puede reenviarla, y solo eso la fecha de nuevo.
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `spaceInvites/gr1_${JORGE}`), {
        spaceId: 'gr1', spaceName: 'Piso', fromUid: JEFA, toUid: JORGE,
        status: 'accepted', createdAt: Timestamp.fromMillis(1_500_000),
        updatedAt: Timestamp.fromMillis(1_500_000),
      }));
    await assertFails(updateDoc(doc(db(JORGE), `spaceInvites/gr1_${JORGE}`), {
      status: 'pending', createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
    // Y la `accepted` antigua tampoco readmite por sí sola.
    await assertFails(aceptarInvitacion(JORGE));
  });

  it('una invitación NUEVA readmite y levanta el bloqueo', async () => {
    await assertSucceeds(invitar(JORGE));
    await assertSucceeds(aceptarInvitacion(JORGE));
    const bloqueo = await getDoc(
      doc(db(JEFA), `spaces/gr1/entryBlocks/${JORGE}`));
    if (bloqueo.exists()) throw new Error('el bloqueo sobrevivió');
    // Y la evidencia de la expulsión anterior permanece intacta.
    const evidencia = await getDoc(
      doc(db(JEFA), `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`));
    if (!evidencia.exists()) throw new Error('se perdió el histórico');
  });

  it('readmitir sin levantar el bloqueo: denegado', async () => {
    await assertSucceeds(invitar(JORGE));
    await assertFails(aceptarInvitacion(JORGE, { levantarBloqueo: false }));
  });

  it('levantar el bloqueo sin readmitir: denegado', async () => {
    await assertSucceeds(invitar(JORGE));
    await assertFails(
      deleteDoc(doc(db(JORGE), `spaces/gr1/entryBlocks/${JORGE}`)));
  });

  it('`createdAt` de una invitación está anclado al servidor', () =>
    assertFails(setDoc(doc(db(JEFA), `spaceInvites/gr1_${JORGE}`), {
      spaceId: 'gr1', spaceName: 'Piso', fromUid: JEFA, toUid: JORGE,
      status: 'pending', createdAt: Timestamp.fromMillis(1),
      updatedAt: serverTimestamp(),
    })));

  it('reinvitar a un expulsado renueva la fecha de la decisión', async () => {
    await assertSucceeds(invitar(JORGE));
    await assertSucceeds(aceptarInvitacion(JORGE));
    // Segunda vuelta: la invitación quedó `accepted` y hay que reutilizarla.
    const joined = (await getDoc(
      doc(db(JEFA), `spaces/gr1/members/${JORGE}`))).data().joinedAt;
    await assertSucceeds(expulsar(JEFA, JORGE, joined));
    await assertSucceeds(updateDoc(doc(db(JEFA), `spaceInvites/gr1_${JORGE}`), {
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(aceptarInvitacion(JORGE));
  });

  it('reenviar SIN renovar la fecha no vale como decisión nueva', async () => {
    await assertFails(updateDoc(doc(db(JEFA), `spaceInvites/gr1_${JORGE}`), {
      status: 'pending', updatedAt: serverTimestamp(),
    }));
  });
});

describe('A11d: ciclos repetidos', () => {
  beforeEach(async () => {
    await sembrar();
    await assertSucceeds(expulsar(JEFA, JORGE, CICLO_A));
    await assertSucceeds(invitar(JORGE));
    await assertSucceeds(aceptarInvitacion(JORGE));
  });

  it('tras readmisión y salida voluntaria, el enlace vuelve a funcionar',
    async () => {
      await assertSucceeds(
        deleteDoc(doc(db(JORGE), `spaces/gr1/members/${JORGE}`)));
      // Salir NO deja bloqueo, y la evidencia de la expulsión anterior sigue
      // ahí: `removals` es HISTORIAL, `entryBlocks` es el bloqueo VIGENTE.
      // Un removal antiguo, por sí solo, no cierra el enlace.
      const evidencia = await getDoc(doc(
        db(JEFA), `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`));
      const bloqueo = await getDoc(
        doc(db(JEFA), `spaces/gr1/entryBlocks/${JORGE}`));
      if (!evidencia.exists()) throw new Error('se perdió el histórico');
      if (bloqueo.exists()) throw new Error('salir dejó bloqueo');
      await assertSucceeds(entrarPorEnlace(JORGE));
    });

  it('la segunda expulsión crea evidencia nueva y bloquea otra vez',
    async () => {
      const joined = (await getDoc(
        doc(db(JEFA), `spaces/gr1/members/${JORGE}`))).data().joinedAt;
      await assertSucceeds(expulsar(JEFA, JORGE, joined));

      const cliente = db(JEFA);
      const evidenciaA = await getDoc(doc(
        cliente, `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`));
      const evidenciaB = await getDoc(doc(
        cliente, `spaces/gr1/removals/${cicloId(JORGE, joined)}`));
      const bloqueo = await getDoc(
        doc(cliente, `spaces/gr1/entryBlocks/${JORGE}`));
      if (!evidenciaA.exists()) throw new Error('la evidencia A se perdió');
      if (!evidenciaB.exists()) throw new Error('falta la evidencia B');
      if (!bloqueo.exists()) throw new Error('el enlace quedó abierto');
      // Y siguen siendo hechos DISTINTOS: el ciclo A conserva su actor.
      if (evidenciaA.data().membershipJoinedAt.toMillis()
        === evidenciaB.data().membershipJoinedAt.toMillis()) {
        throw new Error('las dos evidencias describen el mismo ciclo');
      }
      await assertFails(entrarPorEnlace(JORGE));
    });

  it('el expulsado ve la evidencia que le afecta; un extraño no', async () => {
    await assertSucceeds(getDoc(doc(
      db(JORGE), `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`)));
    await assertFails(getDoc(doc(
      db(AJENA), `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`)));
  });
});

// ── A3: el propietario abandona el grupo ────────────────────────────────
//
// Transferir y salir son UNA operación: dos escrituras en el mismo commit.
// Rules las valida cruzadas, así que ninguno de los estados intermedios que
// harían daño —grupo sin propietario, saliente fuera con el `ownerUid`
// antiguo, o un INVITADO heredando el contexto— llega a existir.
const GUEST = 'uid-guest';
const CICLO_JEFA = Timestamp.fromMillis(1_000_000);

/** Salida del propietario: transferencia + baja, un solo commit. */
const salirTransfiriendo = (actor, sucesor, { spaceId = 'gr1' } = {}) => {
  const f = db(actor);
  const batch = writeBatch(f);
  batch.update(doc(f, `spaces/${spaceId}`), {
    ownerUid: sucesor, updatedAt: serverTimestamp(),
  });
  batch.delete(doc(f, `spaces/${spaceId}/members/${actor}`));
  return batch.commit();
};

describe('A3: salida del propietario y sucesión', () => {
  beforeEach(async () => {
    await sembrar();
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `spaces/gr1/members/${GUEST}`), {
        uid: GUEST, joinedAt: Timestamp.fromMillis(500_000),
        kind: 'guest', displayName: 'Nico',
      }));
  });

  it('sale transfiriendo a un administrador en el mismo commit', async () => {
    await assertSucceeds(salirTransfiriendo(JEFA, ADMIN));
    const espacio = await getDoc(doc(db(ADMIN), 'spaces/gr1'));
    const antigua = await getDoc(doc(db(ADMIN), `spaces/gr1/members/${JEFA}`));
    if (espacio.data().ownerUid !== ADMIN) {
      throw new Error('la propiedad no cambió de manos');
    }
    if (antigua.exists()) throw new Error('la membresía anterior sobrevivió');
  });

  it('también a un miembro normal: la sucesión no exige rol', () =>
    assertSucceeds(salirTransfiriendo(JEFA, JORGE)));

  it('borrar SOLO su membresía deja el grupo sin dueño: denegado', () =>
    assertFails(deleteDoc(doc(db(JEFA), `spaces/gr1/members/${JEFA}`))));

  it('transferirse el grupo a sí mismo no habilita la salida', () =>
    assertFails(salirTransfiriendo(JEFA, JEFA)));

  it('un INVITADO no hereda el contexto', async () => {
    await assertFails(salirTransfiriendo(JEFA, GUEST));
    // Ni siquiera con la transferencia suelta de siempre.
    await assertFails(updateDoc(doc(db(JEFA), 'spaces/gr1'), {
      ownerUid: GUEST, updatedAt: serverTimestamp(),
    }));
  });

  it('no se nombra sucesor a quien no es miembro', () =>
    assertFails(salirTransfiriendo(JEFA, AJENA)));

  it('nombrar sucesor y expulsarlo en el mismo commit: denegado', async () => {
    const f = db(JEFA);
    const batch = writeBatch(f);
    batch.update(doc(f, 'spaces/gr1'), {
      ownerUid: JORGE, updatedAt: serverTimestamp(),
    });
    batch.set(doc(f, `spaces/gr1/removals/${cicloId(JORGE, CICLO_A)}`), {
      uid: JORGE, membershipJoinedAt: CICLO_A, removedBy: JEFA,
      removedAt: serverTimestamp(), schemaVersion: 1,
    });
    batch.set(doc(f, `spaces/gr1/entryBlocks/${JORGE}`), {
      uid: JORGE, membershipJoinedAt: CICLO_A,
      blockedAt: serverTimestamp(), schemaVersion: 1,
    });
    batch.delete(doc(f, `spaces/gr1/members/${JORGE}`));
    await assertFails(batch.commit());
  });

  it('un miembro no saca al propietario disfrazándolo de sucesión', async () => {
    const f = db(JORGE);
    const batch = writeBatch(f);
    batch.update(doc(f, 'spaces/gr1'), {
      ownerUid: JORGE, updatedAt: serverTimestamp(),
    });
    batch.delete(doc(f, `spaces/gr1/members/${JEFA}`));
    await assertFails(batch.commit());
  });

  it('una RELACIÓN no adquiere sucesión: su propietario no sale', async () => {
    await assertFails(salirTransfiriendo(JEFA, PAREJA, { spaceId: 'rel1' }));
    // La otra mitad sigue pudiendo irse por su pie.
    await assertSucceeds(
      deleteDoc(doc(db(PAREJA), `spaces/rel1/members/${PAREJA}`)));
  });

  it('salir NO deja evidencia ni bloquea la reentrada del propietario',
    async () => {
      await assertSucceeds(salirTransfiriendo(JEFA, ADMIN));
      const cliente = db(ADMIN);
      const evidencia = await getDoc(doc(
        cliente, `spaces/gr1/removals/${cicloId(JEFA, CICLO_JEFA)}`));
      const bloqueo = await getDoc(
        doc(cliente, `spaces/gr1/entryBlocks/${JEFA}`));
      if (evidencia.exists()) throw new Error('una salida dejó evidencia');
      if (bloqueo.exists()) throw new Error('una salida dejó bloqueo');
    });

  // Residual conocido: la transferencia exige el espacio ACTIVO, así que el
  // propietario de un grupo archivado reactiva antes de salir. La interfaz
  // tampoco le ofrece la acción mientras esté archivado.
  it('en un grupo ARCHIVADO la salida del propietario no está abierta',
    async () => {
      await assertSucceeds(updateDoc(doc(db(JEFA), 'spaces/gr1'), {
        status: 'archived', updatedAt: serverTimestamp(),
      }));
      await assertFails(salirTransfiriendo(JEFA, ADMIN));
    });
});
