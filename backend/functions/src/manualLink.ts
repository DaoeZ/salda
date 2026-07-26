/**
 * Propagación de una vinculación MANUAL ↔ identidad (ADR-037, corrige C1).
 *
 * EL PROBLEMA. `recompute` lee los alias del espacio, pero escribir
 * `linkedUid` no disparaba nada: los `economicEntries` conservaban su
 * `memberUids` anterior y la persona no obtenía acceso hasta que alguien
 * editaba un ticket por otro motivo. La app decía «vinculado» y no lo estaba.
 *
 * POR QUÉ REPROYECTAR Y NO RESOLVER AL LEER. Resolver el alias en la consulta
 * exigiría que el cliente buscara además por `debtorUid`/`creditorUid` y que
 * las Rules autorizaran cada documento con un get() sobre el espacio — caro,
 * con límites por página, y sobre todo obligaría a consolidar saldos EN EL
 * CLIENTE, rompiendo DC-7 (la function es la calculadora autoritativa; los
 * clientes solo pintan). Además la supresión de deudas consigo mismo (C2)
 * tiene que ocurrir en el motor, así que resolver C1 al leer y C2 al calcular
 * dejaría justo el modelo híbrido que hay que evitar.
 *
 * ESTADO EXPLÍCITO. El vínculo nace `processing` y solo pasa a `active`
 * cuando TODAS las sesiones del espacio se han reproyectado. La UI muestra
 * «vinculando…» mientras tanto: nunca afirma acceso que no exista todavía.
 * Si algo falla, queda `failed` con el motivo, y reintentar es seguro porque
 * `recomputeSession` es idempotente y solo escribe si algo cambió.
 */
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

import { recomputeSession } from './recompute.js';

export type LinkStatus = 'processing' | 'active' | 'failed';

/**
 * Reproyecta todas las sesiones del espacio y publica el resultado.
 *
 * Idempotente por partida doble: `recomputeSession` converge y solo escribe
 * si hay cambio, y volver a llamar aquí con el vínculo ya `active` repite el
 * trabajo sin efecto observable.
 */
export async function propagateManualLink(
  spaceId: string,
  manualId: string,
): Promise<{ sessions: number; status: LinkStatus; reason?: string }> {
  const db = getFirestore();
  const manualRef = db.doc(`spaces/${spaceId}/manualParticipants/${manualId}`);

  // CRITERIO REAL de afectación: las sesiones que tienen un participante con
  // ESE manualId. Buscar por `sessions.spaceId` era incorrecto — `linkTicket`
  // vincula el TICKET a un espacio sin tocar la sesión, así que una sesión
  // afectada podía quedar fuera de la consulta y el vínculo se marcaba
  // `active` habiendo omitido economía (M3).
  const affected = await db
    .collectionGroup('participants')
    .where('manualId', '==', manualId)
    .get();

  const sessionIds = new Set<string>();
  for (const participant of affected.docs) {
    const session = participant.ref.parent.parent;
    if (session) sessionIds.add(session.id);
  }

  try {
    // M3: una sesión afectada SIN contexto estable no puede resolver alias
    // —recompute los lee del espacio de la sesión—, así que reproyectarla
    // dejaría el vínculo a medias en silencio. Se detiene con motivo claro
    // en vez de terminar `active` habiendo omitido a alguien.
    const orphans: string[] = [];
    for (const sid of sessionIds) {
      const session = await db.doc(`sessions/${sid}`).get();
      if (!session.exists) continue; // borrada durante la propagación: no aplica
      if (!session.data()?.spaceId) orphans.push(sid);
    }
    if (orphans.length > 0) {
      await manualRef.update({
        linkStatus: 'failed',
        // Motivo estable y sin datos sensibles: la app lo traduce a un texto
        // comprensible. El detalle completo vive solo en logs.
        linkError: 'legacy-sessions-without-context',
        linkBlockedSessions: orphans.length,
      });
      logger.warn('propagateManualLink: sesiones sin contexto', {
        spaceId, manualId, orphans,
      });
      return {
        sessions: sessionIds.size,
        status: 'failed',
        reason: 'legacy-sessions-without-context',
      };
    }

    // Secuencial a propósito: recompute escribe agregados y dispara sus
    // propios triggers; en paralelo multiplicaría la contención sobre los
    // mismos documentos sin ganar nada a esta escala.
    for (const sid of sessionIds) {
      await recomputeSession(sid);
    }
    await manualRef.update({
      linkStatus: 'active',
      linkPropagatedSessions: sessionIds.size,
      linkPropagatedAt: FieldValue.serverTimestamp(),
      linkError: FieldValue.delete(),
      linkBlockedSessions: FieldValue.delete(),
    });
    return { sessions: sessionIds.size, status: 'active' };
  } catch (error) {
    // No se marca `active`: el sistema no puede afirmar que la vinculación
    // está viva mientras queden sesiones sin reproyectar. `failed` es
    // reintentable: recomputeSession converge y solo escribe si algo cambió.
    logger.error('propagateManualLink falló', { spaceId, manualId, error });
    await manualRef.update({
      linkStatus: 'failed',
      // Código estable, NO el error crudo: un mensaje de Firestore puede
      // llevar rutas o ids ajenos y este documento lo leen los miembros.
      linkError: 'propagation-error',
    });
    return {
      sessions: sessionIds.size,
      status: 'failed',
      reason: 'propagation-error',
    };
  }
}

/**
 * Dispara la propagación cuando `linkedUid` pasa de ausente a presente.
 *
 * Solo esa transición: renombrar el manual, o cualquier escritura posterior
 * del propio propagador (linkStatus, marcas de tiempo), no vuelve a entrar.
 * Sin ese filtro el trigger se realimentaría en bucle.
 */
export const propagateOnManualLink = onDocumentWritten(
  'spaces/{spaceId}/manualParticipants/{manualId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;
    const linkedBefore = (before?.linkedUid as string | undefined) ?? null;
    const linkedAfter = (after.linkedUid as string | undefined) ?? null;
    if (linkedAfter === null) return;
    const statusBefore = before?.linkStatus as string | undefined;
    const statusAfter = after.linkStatus as string | undefined;
    // Dos entradas legítimas: la vinculación inicial, y un REINTENTO que el
    // propietario dispara devolviendo el estado a `processing` desde
    // `failed`. Cualquier otra escritura (renombrar, o las marcas del propio
    // propagador) no vuelve a entrar: sin este filtro el trigger se
    // realimentaría en bucle.
    const esAlta = linkedBefore === null;
    const esReintento =
      statusBefore === 'failed' && statusAfter === 'processing';
    if (!esAlta && !esReintento) return;
    await propagateManualLink(
      event.params.spaceId,
      event.params.manualId,
    );
  },
);
