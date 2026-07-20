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

    await getStorage()
      .bucket()
      .deleteFiles({ prefix: `receipts/${sid}/` })
      .catch((error: unknown) => {
        // Sin bucket (emulador sin storage) o sin archivos: no es un fallo.
        logger.debug('Storage cleanup omitido', { sid, error: `${error}` });
      });

    logger.info('Sesión purgada', { sid });
  },
);
