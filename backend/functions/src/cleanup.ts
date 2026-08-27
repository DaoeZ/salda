/**
 * cleanup — borrado en cascada (spec §12.2).
 *
 * Al borrar el documento de una sesión (solo puede el owner, ver reglas),
 * se eliminan todas sus subcolecciones y las imágenes de Storage. Con
 * reintentos activados: un fallo transitorio no deja huérfanos.
 */
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions/v2';
import { onDocumentDeleted } from 'firebase-functions/v2/firestore';

import { recomputeSession } from './recompute.js';

export const cleanupOnSessionDelete = onDocumentDeleted(
  { document: 'sessions/{sid}', retry: true },
  async (event) => {
    const sid = event.params.sid;
    const db = getFirestore();

    // recursiveDelete elimina las subcolecciones aunque el doc ya no exista.
    await db.recursiveDelete(db.doc(`sessions/${sid}`));

    // P5 materializa únicamente vistas reconstruibles fuera de la sesión.
    // La cascada elimina sus derivados; pagos globales de usuario NO llevan
    // sourceSessionId y conservan el historial humano.
    const [entries, legacyPayments] = await Promise.all([
      db.collection('economicEntries').where('sessionId', '==', sid).get(),
      db.collection('economicPayments').where('sourceSessionId', '==', sid).get(),
    ]);
    const writer = db.bulkWriter();
    for (const doc of entries.docs) writer.delete(doc.ref);
    for (const doc of legacyPayments.docs) {
      if (doc.data().source === 'legacySettlement') writer.delete(doc.ref);
    }
    await writer.close();

    // Sin bucket (emulador sin storage) o sin archivos: no es un fallo. El
    // try/catch cubre además el lanzamiento SÍNCRONO de `bucket()` cuando no
    // hay bucket configurado, que un `.catch()` dejaba escapar.
    try {
      await getStorage().bucket().deleteFiles({ prefix: `receipts/${sid}/` });
    } catch (error: unknown) {
      logger.debug('Storage cleanup omitido', { sid, error: `${error}` });
    }

    logger.info('Sesión purgada', { sid });
  },
);

/**
 * A2 — purga de UN gasto eliminado (ADR-040).
 *
 * Borrar el documento del ticket no basta: sus `lines` son una subcolección y
 * sobreviven, dejando además un «documento fantasma» que sigue apareciendo en
 * `listDocuments()`. Y hay accesos que perderían su objeto: enlaces del
 * ticket, identificaciones, cerrojos, el derecho histórico de A11d y la foto.
 *
 * Todo lo que hay aquí es DERIVADO del ticket y está acotado a él: nunca toca
 * otros tickets, ni la sesión, ni los pagos, ni la actividad, ni la evidencia
 * `ticketRemovals` —que es justamente lo que explica el borrado después—.
 *
 * Idempotente por construcción (borrados por id o por consulta acotada), y
 * con `retry` para que un fallo transitorio no deje huérfanos.
 */
export async function purgeDeletedTicket(
  sid: string,
  aid: string,
  tid: string,
): Promise<void> {
  const db = getFirestore();
  const sessionRef = db.doc(`sessions/${sid}`);
  const accountRef = sessionRef.collection('accounts').doc(aid);

  // Líneas y documento fantasma de una vez.
  await db.recursiveDelete(accountRef.collection('tickets').doc(tid));

  // Derivados del ticket, por consulta acotada a SU id.
  const [access, claims, entitlements, links] = await Promise.all([
    sessionRef.collection('ticketAccess').where('ticketId', '==', tid).get(),
    sessionRef.collection('ticketClaims').where('ticketId', '==', tid).get(),
    sessionRef.collection('ticketEntitlements')
      .where('ticketId', '==', tid).get(),
    // Un enlace de ticket vive en la RAÍZ. Se filtra por `ticketId` (índice
    // de campo único, sin compuesto) y se comprueba la sesión en memoria:
    // dos sesiones distintas no comparten id de ticket, pero la
    // comprobación cuesta cero y acota el borrado de forma demostrable.
    db.collection('ticketLinks').where('ticketId', '==', tid).get(),
  ]);
  const writer = db.bulkWriter();
  for (const doc of [...access.docs, ...claims.docs, ...entitlements.docs]) {
    writer.delete(doc.ref);
  }
  for (const doc of links.docs) {
    if (doc.data().sessionId === sid) writer.delete(doc.ref);
  }
  await writer.close();

  // La cuenta contenedora es un envoltorio de un solo ticket en el modelo
  // actual. Se retira solo si de verdad queda vacía, y con
  // `listDocuments()` porque un fantasma no aparecería en un `get()`.
  const restantes = await accountRef.collection('tickets').listDocuments();
  if (restantes.length === 0) await accountRef.delete().catch(() => {});

  // La foto sigue al gasto: el ticket dejó de existir a propósito y no hay
  // ninguna superficie que pueda volver a autorizarla.
  //
  // try/catch y no `.catch()`: sin bucket configurado, `bucket()` lanza de
  // forma SÍNCRONA y la promesa nunca llega a existir. Con `retry: true` eso
  // dejaba la purga reintentándose para siempre después de haber hecho ya su
  // trabajo en Firestore.
  try {
    await getStorage()
      .bucket()
      .deleteFiles({ prefix: `receipts/${sid}/${tid}/` });
  } catch (error: unknown) {
    logger.debug('Storage cleanup omitido', { sid, tid, error: `${error}` });
  }

  // Última pasada de agregados. `recompute` ya converge solo por sus
  // propios triggers, pero esta purga borra la CUENTA, y un recompute que
  // la hubiera leído justo antes fallaría al actualizarla. Repetirlo aquí
  // —idempotente— garantiza el estado final sin tocar recompute.
  await recomputeSession(sid);

  logger.info('Gasto purgado', { sid, aid, tid });
}

export const cleanupOnTicketDelete = onDocumentDeleted(
  { document: 'sessions/{sid}/accounts/{aid}/tickets/{tid}', retry: true },
  (event) => purgeDeletedTicket(
    event.params.sid, event.params.aid, event.params.tid),
);
