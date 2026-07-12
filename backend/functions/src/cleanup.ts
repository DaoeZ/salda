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
