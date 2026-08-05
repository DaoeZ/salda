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
 * ESTADO EXPLÍCITO. La aprobación publica `accepted + linkedUid`; el trigger
 * reclama con `processing`. Solo pasa a `active` cuando TODAS las
 * sesiones del espacio se han reproyectado. Si algo falla, queda `failed` con
 * el motivo.
 */
import {
  getFirestore,
  FieldValue,
  type DocumentSnapshot,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

import { recomputeSession } from './recompute.js';

export type LinkStatus = 'processing' | 'active' | 'failed';

type ManualLinkClaim =
  | { kind: 'initial'; linkedUid: string }
  | { kind: 'retry'; linkedUid: string; linkError: string };

const manualLinkRef = (spaceId: string, manualId: string) =>
  getFirestore().doc(`spaces/${spaceId}/manualParticipants/${manualId}`);

const statusOf = (data: Record<string, unknown> | undefined): LinkStatus =>
  data?.linkStatus === 'failed' || data?.linkStatus === 'active'
    ? data.linkStatus
    : 'processing';

const claimForDocument = (
  data: Record<string, unknown> | undefined,
): ManualLinkClaim | null => {
  if (typeof data?.linkedUid !== 'string') return null;
  if (data.linkStatus === undefined) {
    return { kind: 'initial', linkedUid: data.linkedUid };
  }
  if (data.linkStatus === 'processing' && typeof data.linkError === 'string') {
    return { kind: 'retry', linkedUid: data.linkedUid, linkError: data.linkError };
  }
  return null;
};

const claimForTransition = (
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): ManualLinkClaim | null => {
  const current = claimForDocument(after);
  if (current?.kind === 'initial') {
    const linkedBefore =
      typeof before?.linkedUid === 'string' && before.linkedUid.length > 0;
    return linkedBefore ? null : current;
  }
  return before?.linkStatus === 'failed' && current?.kind === 'retry'
    ? current
    : null;
};

/** Reclama una versión concreta: una misma entrega solo puede ganar una vez. */
export async function claimManualLinkPropagation(
  spaceId: string,
  manualId: string,
  expected: ManualLinkClaim,
): Promise<boolean> {
  const db = getFirestore();
  const manualRef = manualLinkRef(spaceId, manualId);
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(manualRef);
    const data = current.data();
    if (
      !current.exists ||
      data?.linkedUid !== expected.linkedUid ||
      (expected.kind === 'initial'
        ? data?.linkStatus !== undefined
        : data?.linkStatus !== 'processing' ||
          data?.linkError !== expected.linkError)
    ) {
      return false;
    }
    transaction.update(manualRef, {
      linkStatus: 'processing',
      linkError: FieldValue.delete(),
      linkBlockedSessions: FieldValue.delete(),
      linkPropagatedSessions: FieldValue.delete(),
      linkPropagatedAt: FieldValue.delete(),
    });
    return true;
  });
}

/** Publica un terminal solo para la reclamación que sigue en curso. */
export async function publishManualLinkTerminal(
  spaceId: string,
  manualId: string,
  linkedUid: string,
  status: Extract<LinkStatus, 'active' | 'failed'>,
  fields: Record<string, unknown>,
): Promise<boolean> {
  const db = getFirestore();
  const manualRef = manualLinkRef(spaceId, manualId);
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(manualRef);
    const data = current.data();
    if (
      !current.exists ||
      data?.linkedUid !== linkedUid ||
      data?.linkStatus !== 'processing'
    ) {
      return false;
    }
    transaction.update(manualRef, { linkStatus: status, ...fields });
    return true;
  });
}

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
  const manualRef = manualLinkRef(spaceId, manualId);
  const after = await manualRef.get();
  const claim = claimForDocument(after.data());
  if (
    !after.exists ||
    !claim ||
    !await claimManualLinkPropagation(spaceId, manualId, claim)
  ) {
    return { sessions: 0, status: statusOf(after.data()) };
  }
  return propagateClaimedManualLink(spaceId, manualId, claim.linkedUid);
}

async function propagateClaimedManualLink(
  spaceId: string,
  manualId: string,
  linkedUid: string,
): Promise<{ sessions: number; status: LinkStatus; reason?: string }> {
  const db = getFirestore();

  // CRITERIO REAL de afectación: las sesiones que tienen un participante con
  // ESE manualId. Buscar por `sessions.spaceId` era incorrecto — `linkTicket`
  // vincula el TICKET a un espacio sin tocar la sesión, así que una sesión
  // afectada podía quedar fuera de la consulta y el vínculo se marcaba
  // `active` habiendo omitido economía (M3).
  const sessionIds = new Set<string>();

  try {
    // Mantener la consulta dentro del bloque controlado permite publicar
    // `failed` incluso si falla la lectura de las sesiones afectadas.
    const affected = await db
      .collectionGroup('participants')
      .where('manualId', '==', manualId)
      .get();
    for (const participant of affected.docs) {
      const session = participant.ref.parent.parent;
      if (session) sessionIds.add(session.id);
    }

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
      await publishManualLinkTerminal(spaceId, manualId, linkedUid, 'failed', {
        // Motivo estable y sin datos sensibles: la app lo traduce a un texto
        // comprensible. El detalle completo vive solo en logs.
        linkError: 'legacy-sessions-without-context',
        linkBlockedSessions: orphans.length,
        linkPropagatedSessions: FieldValue.delete(),
        linkPropagatedAt: FieldValue.delete(),
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
    await publishManualLinkTerminal(spaceId, manualId, linkedUid, 'active', {
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
    await publishManualLinkTerminal(spaceId, manualId, linkedUid, 'failed', {
      // Código estable, NO el error crudo: un mensaje de Firestore puede
      // llevar rutas o ids ajenos y este documento lo leen los miembros.
      linkError: 'propagation-error',
      linkBlockedSessions: FieldValue.delete(),
      linkPropagatedSessions: FieldValue.delete(),
      linkPropagatedAt: FieldValue.delete(),
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
 * Solo esa transición y el reintento `failed -> processing`: renombrar el
 * manual, o cualquier escritura posterior del propio propagador (linkStatus,
 * marcas de tiempo), no vuelve a entrar.
 */
export function shouldPropagateManualLink(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): boolean {
  return claimForTransition(before, after) !== null;
}

/** Ejecuta exactamente la ruta del trigger para una versión concreta. */
export async function handleManualLinkWrite(
  spaceId: string,
  manualId: string,
  before: Record<string, unknown> | undefined,
  after: DocumentSnapshot | undefined,
): Promise<void> {
  const afterData = after?.data();
  const claim = claimForTransition(before, afterData);
  if (!claim) return;
  if (!await claimManualLinkPropagation(spaceId, manualId, claim)) return;
  await propagateClaimedManualLink(spaceId, manualId, claim.linkedUid);
}

export const propagateOnManualLink = onDocumentWritten(
  'spaces/{spaceId}/manualParticipants/{manualId}',
  async (event) => {
    await handleManualLinkWrite(
      event.params.spaceId,
      event.params.manualId,
      event.data?.before.data(),
      event.data?.after,
    );
  },
);
