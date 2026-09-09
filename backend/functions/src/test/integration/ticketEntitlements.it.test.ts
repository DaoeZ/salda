/**
 * A11d — el derecho histórico contra Firestore real (emulador).
 *
 * Lo que la función pura no puede demostrar y aquí sí: que recompute lo
 * PERSISTE, que no lo retira nunca aunque el reparto cambie, y —lo más
 * fácil de romper— que el atajo «si nada cambió, no escribas» no se salta la
 * creación de un derecho que falta. Ese atajo dejaría la proyección
 * incompleta justo en los tickets que llevan tiempo quietos, que son
 * precisamente los que alguien va a auditar después de que lo expulsen.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { recomputeSession } from '../../recompute.js';
import { clearFirestore, db, disposeApp, emulatorAvailable } from './harness.js';

const ALBA = 'uid-alba';
const JORGE = 'uid-jorge';
const GRUPO = 'grupo-piso';

const entitlement = (tid: string, uid: string) =>
  db().doc(`sessions/s1/ticketEntitlements/${tid}_${uid}`);

describe('A11d: derecho histórico persistido', { skip: !emulatorAvailable() },
  () => {
    before(() => {
      process.env.GOOGLE_CLOUD_PROJECT ??= 'demo-salda';
    });
    after(disposeApp);
    beforeEach(clearFirestore);

    /** Grupo, sesión y un ticket que Alba paga y Jorge consume a medias. */
    async function seed(): Promise<void> {
      const f = db();
      await f.doc(`spaces/${GRUPO}`).set({
        name: 'Piso', ownerUid: ALBA, kind: 'group', status: 'active',
        schemaVersion: 2,
      });
      for (const uid of [ALBA, JORGE]) {
        await f.doc(`spaces/${GRUPO}/members/${uid}`).set({ uid });
        await f.doc(`profiles/${uid}`).set({ displayName: uid });
      }
      await f.doc('sessions/s1').set({
        ownerUid: ALBA, kind: 'single', status: 'open',
        splitModeDefault: 'byItem', currency: 'EUR', spaceId: GRUPO,
        contextModelVersion: 1, computeVersion: 0, totals: {}, balances: {},
      });
      await f.doc('sessions/s1/participants/p1').set({
        name: 'Alba', isOwner: true, order: 0, active: true,
        claimedByDevice: '',
      });
      await f.doc('sessions/s1/participants/p2').set({
        name: 'Jorge', isOwner: false, order: 1, active: true,
        claimedByDevice: JORGE,
      });
      await f.doc('sessions/s1/accounts/a1').set({ name: 'Compra', totals: {} });
      await f.doc('sessions/s1/accounts/a1/tickets/t1').set({
        kind: 'manual', grandTotal: 3000, paidByParticipantId: 'p1',
        merchant: { name: 'Super' }, spaceId: GRUPO,
      });
      await f.doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').set({
        name: 'Lo de Alba', totalPrice: 1000, order: 0,
        assignment: { type: 'one', participants: { p1: 1 } },
      });
      await f.doc('sessions/s1/accounts/a1/tickets/t1/lines/l2').set({
        name: 'Lo de Jorge', totalPrice: 2000, order: 1,
        assignment: { type: 'one', participants: { p2: 1 } },
      });
    }

    it('recompute lo escribe con cuenta y nombres del reparto', async () => {
      await seed();
      await recomputeSession('s1');

      const jorge = await entitlement('t1', JORGE).get();
      assert.ok(jorge.exists, 'Jorge participó y no tiene derecho');
      assert.equal(jorge.data()?.accountId, 'a1');
      assert.equal(jorge.data()?.uid, JORGE);
      assert.deepEqual(jorge.data()?.participantNames,
        { p1: 'Alba', p2: 'Jorge' });
      // El pagador también: es el acreedor del gasto.
      assert.ok((await entitlement('t1', ALBA).get()).exists);
    });

    it('una corrección A11c posterior NO lo retira', async () => {
      await seed();
      await recomputeSession('s1');
      assert.ok((await entitlement('t1', JORGE).get()).exists);

      // Un administrador retira la línea de Jorge (A11c).
      await db()
        .doc('sessions/s1/accounts/a1/tickets/t1/lines/l2').delete();
      await db().doc('sessions/s1/accounts/a1/tickets/t1')
        .update({ grandTotal: 1000 });
      await recomputeSession('s1');

      // Su obligación desaparece de la economía vigente…
      const entradas = await db().collection('economicEntries')
        .where('memberUids', 'array-contains', JORGE).get();
      assert.equal(entradas.size, 0);
      // …y la foto del reparto vivo también lo suelta…
      const vivo = await db()
        .doc(`sessions/s1/ticketParticipants/t1_p2`).get();
      assert.equal(vivo.exists, false);
      // …pero el derecho histórico SIGUE ahí: es lo único con lo que puede
      // auditar el gasto que ya pagó.
      assert.ok((await entitlement('t1', JORGE).get()).exists,
        'la corrección borró el derecho histórico');
    });

    it('se crea aunque el resto del recompute resulte «sin cambios»',
      async () => {
        await seed();
        await recomputeSession('s1');
        // Se borra a mano: simula una sesión anterior a A11d, o un fallo
        // parcial. La economía ya está calculada y no va a cambiar.
        await entitlement('t1', JORGE).delete();

        await recomputeSession('s1');

        assert.ok((await entitlement('t1', JORGE).get()).exists,
          'el atajo `unchanged` se saltó la creación del derecho');
      });

    it('recomputes repetidos no reescriben lo ya concedido', async () => {
      await seed();
      await recomputeSession('s1');
      const primero = (await entitlement('t1', JORGE).get()).data();
      await recomputeSession('s1');
      await recomputeSession('s1');
      const despues = (await entitlement('t1', JORGE).get()).data();
      // `grantedAt` es la fecha de la concesión: no se renueva.
      assert.deepEqual(
        (primero?.grantedAt as { toMillis(): number }).toMillis(),
        (despues?.grantedAt as { toMillis(): number }).toMillis(),
      );
    });

    it('quien no participa económicamente no obtiene derecho', async () => {
      await seed();
      // Marta es miembro del grupo y participante de la sesión, pero no
      // consume nada de este ticket ni lo paga.
      await db().doc('sessions/s1/participants/p3').set({
        name: 'Marta', isOwner: false, order: 2, active: true,
        claimedByDevice: 'uid-marta',
      });
      await db().doc('profiles/uid-marta').set({ displayName: 'Marta' });
      await recomputeSession('s1');

      assert.equal((await entitlement('t1', 'uid-marta').get()).exists, false);
    });
  });
