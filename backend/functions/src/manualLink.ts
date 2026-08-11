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
 * o el callable reclaman con `processing`. Solo pasa a `active` cuando TODAS
 * las sesiones del espacio se han reproyectado. Si algo falla, queda `failed`
 * con el motivo. Cada worker conserva un claim opaco y el terminal se publica
 * con compare-and-set para que una recuperación no pueda ser pisada por un
 * worker antiguo.
 */
import {
  getFirestore,
  FieldValue,
  Timestamp,
  type DocumentReference,
  type DocumentSnapshot,
  type Transaction,
} from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

import { recomputeSession } from './recompute.js';

export type LinkStatus = 'processing' | 'active' | 'failed';

const PROCESSING_LEASE_MS = 5 * 60 * 1000;
const RETRY_COOLDOWN_MS = 30 * 1000;
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9][A-Za-z0-9_.~-]{0,127}$/;

type ManualLinkRetryAction =
  | 'claimed'
  | 'active'
  | 'in-progress'
  | 'unclassifiable'
  | 'cooldown';

type ManualLinkClaim =
  | { kind: 'initial'; linkedUid: string }
  | { kind: 'retry'; linkedUid: string; linkError: string };

type ManualLinkClaimHandle = {
  linkedUid: string;
  claimId: string;
};

const manualLinkRef = (spaceId: string, manualId: string) =>
  getFirestore().doc(`spaces/${spaceId}/manualParticipants/${manualId}`);

const statusOf = (data: Record<string, unknown> | undefined): LinkStatus =>
  data?.linkStatus === 'failed' || data?.linkStatus === 'active'
    ? data.linkStatus
    : 'processing';

const claimForDocument = (
  data: Record<string, unknown> | undefined,
): ManualLinkClaim | null => {
  if (typeof data?.linkedUid !== 'string' || data.linkedUid.length === 0) {
    return null;
  }
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

const timestampOf = (value: unknown): Timestamp | null =>
  value && typeof (value as Timestamp).toMillis === 'function'
    ? value as Timestamp
    : null;

const validDocumentId = (value: unknown): value is string =>
  typeof value === 'string'
  && value !== '.'
  && value !== '..'
  && SAFE_DOCUMENT_ID.test(value);

const claimUpdate = (
  transaction: Transaction,
  manualRef: DocumentReference,
  data: Record<string, unknown>,
  kind: ManualLinkClaim['kind'],
  requestedBy?: string,
): ManualLinkClaimHandle => {
  const linkedUid = data.linkedUid as string;
  const claimId = randomUUID();
  const currentRetryCount =
    typeof data.linkRetryCount === 'number'
    && Number.isInteger(data.linkRetryCount)
      ? data.linkRetryCount
      : 0;
  transaction.update(manualRef, {
    linkStatus: 'processing',
    linkClaimId: claimId,
    linkProcessingAt: FieldValue.serverTimestamp(),
    linkError: FieldValue.delete(),
    linkBlockedSessions: FieldValue.delete(),
    linkPropagatedSessions: FieldValue.delete(),
    linkPropagatedAt: FieldValue.delete(),
    ...(kind === 'retry'
      ? { linkRetryCount: currentRetryCount + 1 }
      : {}),
    ...(requestedBy
      ? {
        linkRetryRequestedAt: FieldValue.serverTimestamp(),
        linkRetryRequestedBy: requestedBy,
      }
      : {}),
  });
  return { linkedUid, claimId };
};

/** Reclama una versión concreta: una misma entrega solo puede ganar una vez. */
async function acquireManualLinkPropagation(
  spaceId: string,
  manualId: string,
  expected: ManualLinkClaim,
): Promise<ManualLinkClaimHandle | null> {
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
      return null;
    }
    if (!data) return null;
    return claimUpdate(transaction, manualRef, data, expected.kind);
  });
}

export async function claimManualLinkPropagation(
  spaceId: string,
  manualId: string,
  expected: ManualLinkClaim,
): Promise<boolean> {
  return Boolean(await acquireManualLinkPropagation(spaceId, manualId, expected));
}

/** Publica un terminal solo para la reclamación que sigue en curso. */
export async function publishManualLinkTerminal(
  spaceId: string,
  manualId: string,
  linkedUid: string,
  claimId: string,
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
      data?.linkStatus !== 'processing' ||
      data?.linkClaimId !== claimId
    ) {
      return false;
    }
    transaction.update(manualRef, {
      ...fields,
      linkStatus: status,
      linkClaimId: FieldValue.delete(),
      linkProcessingAt: FieldValue.delete(),
    });
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
  if (!after.exists || !claim) {
    return { sessions: 0, status: statusOf(after.data()) };
  }
  const acquired = await acquireManualLinkPropagation(spaceId, manualId, claim);
  if (!acquired) return { sessions: 0, status: statusOf(after.data()) };
  return propagateClaimedManualLink(
    spaceId,
    manualId,
    acquired.linkedUid,
    acquired.claimId,
  );
}

async function propagateClaimedManualLink(
  spaceId: string,
  manualId: string,
  linkedUid: string,
  claimId: string,
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
      const published = await publishManualLinkTerminal(
        spaceId,
        manualId,
        linkedUid,
        claimId,
        'failed',
        {
          // Motivo estable y sin datos sensibles: la app lo traduce a un texto
          // comprensible. El detalle completo vive solo en logs.
          linkError: 'legacy-sessions-without-context',
          linkBlockedSessions: orphans.length,
          linkPropagatedSessions: FieldValue.delete(),
          linkPropagatedAt: FieldValue.delete(),
        },
      );
      logger.warn('propagateManualLink: sesiones sin contexto', {
        spaceId, manualId, orphans,
      });
      if (!published) return currentClaimResult(spaceId, manualId, sessionIds.size);
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
    const published = await publishManualLinkTerminal(
      spaceId,
      manualId,
      linkedUid,
      claimId,
      'active',
      {
        linkPropagatedSessions: sessionIds.size,
        linkPropagatedAt: FieldValue.serverTimestamp(),
        linkError: FieldValue.delete(),
        linkBlockedSessions: FieldValue.delete(),
      },
    );
    if (!published) return currentClaimResult(spaceId, manualId, sessionIds.size);
    return { sessions: sessionIds.size, status: 'active' };
  } catch (error) {
    // No se marca `active`: el sistema no puede afirmar que la vinculación
    // está viva mientras queden sesiones sin reproyectar. `failed` es
    // reintentable: recomputeSession converge y solo escribe si algo cambió.
    logger.error('propagateManualLink falló', { spaceId, manualId, error });
    const published = await publishManualLinkTerminal(
      spaceId,
      manualId,
      linkedUid,
      claimId,
      'failed',
      {
        // Código estable, NO el error crudo: un mensaje de Firestore puede
        // llevar rutas o ids ajenos y este documento lo leen los miembros.
        linkError: 'propagation-error',
        linkBlockedSessions: FieldValue.delete(),
        linkPropagatedSessions: FieldValue.delete(),
        linkPropagatedAt: FieldValue.delete(),
      },
    );
    if (!published) return currentClaimResult(spaceId, manualId, sessionIds.size);
    return {
      sessions: sessionIds.size,
      status: 'failed',
      reason: 'propagation-error',
    };
  }
}

const currentClaimResult = async (
  spaceId: string,
  manualId: string,
  sessions: number,
): Promise<{ sessions: number; status: LinkStatus; reason?: string }> => {
  const current = await manualLinkRef(spaceId, manualId).get();
  return {
    sessions,
    status: statusOf(current.data()),
    reason: 'claim-lost',
  };
};

const parseRetryInput = (data: unknown): { spaceId: string; manualId: string } => {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
  }
  const input = data as Record<string, unknown>;
  const keys = Object.keys(input).sort();
  if (
    keys.length !== 2 ||
    keys[0] !== 'manualId' ||
    keys[1] !== 'spaceId' ||
    !validDocumentId(input.spaceId) ||
    !validDocumentId(input.manualId)
  ) {
    throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
  }
  return { spaceId: input.spaceId, manualId: input.manualId };
};

type ManualLinkRequestInput = {
  spaceId: string;
  manualId: string;
  displayName: string;
  viaSessionId: string;
  viaTicketId: string;
  viaPid: string;
};

const parseManualLinkRequestInput = (data: unknown): ManualLinkRequestInput => {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
  }
  const input = data as Record<string, unknown>;
  const allowedKeys = new Set([
    'spaceId', 'manualId', 'displayName',
    'viaSessionId', 'viaTicketId', 'viaPid',
  ]);
  if (Object.keys(input).some((key) => !allowedKeys.has(key))) {
    throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
  }
  const optional = (key: 'viaSessionId' | 'viaTicketId' | 'viaPid') => {
    const value = input[key] ?? '';
    if (
      typeof value !== 'string'
      || value.length > 128
      || (value.length > 0 && !validDocumentId(value))
    ) {
      throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
    }
    return value;
  };
  const displayName = typeof input.displayName === 'string'
    ? input.displayName.trim()
    : '';
  if (
    !validDocumentId(input.spaceId)
    || !validDocumentId(input.manualId)
    || displayName.length === 0
    || displayName.length > 40
  ) {
    throw new HttpsError('invalid-argument', 'MANUAL_LINK_DATA_INVALID');
  }
  return {
    spaceId: input.spaceId,
    manualId: input.manualId,
    displayName,
    viaSessionId: optional('viaSessionId'),
    viaTicketId: optional('viaTicketId'),
    viaPid: optional('viaPid'),
  };
};

const requireFullAccount = (
  auth: { uid: string; token: Record<string, unknown> } | undefined,
): string => {
  if (!auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  const firebase = auth.token.firebase as Record<string, unknown> | undefined;
  if (
    auth.token.email_verified !== true
    || firebase?.sign_in_provider === 'anonymous'
  ) {
    throw new HttpsError('permission-denied', 'FULL_ACCOUNT_REQUIRED');
  }
  return auth.uid;
};

type ManualLinkRequestDecision = {
  action: 'created' | 'pending' | 'accepted' | 'rejected' | 'terminal';
};

/**
 * Solicitud autoritativa de vinculación. El cliente no aporta ni UID ni
 * propietario: ambos se fijan desde el estado actual dentro de la transacción.
 */
export const requestManualLink = onCall(async (request) => {
  const uid = requireFullAccount(request.auth);
  const input = parseManualLinkRequestInput(request.data);
  const db = getFirestore();
  const spaceRef = db.doc(`spaces/${input.spaceId}`);
  const manualRef = manualLinkRef(input.spaceId, input.manualId);
  const profileRef = db.doc(`profiles/${uid}`);
  const identityRef = db.doc(`spaces/${input.spaceId}/linkedIdentities/${uid}`);
  const requestRef = db.doc(
    `spaces/${input.spaceId}/manualLinkRequests/${input.manualId}_${uid}`,
  );
  const memberRef = db.doc(`spaces/${input.spaceId}/members/${uid}`);

  const decision = await db.runTransaction<ManualLinkRequestDecision>(
    async (transaction) => {
      const [profile, space, manual, identity, existing, member] =
        await transaction.getAll(
          profileRef, spaceRef, manualRef, identityRef, requestRef, memberRef,
        );
      if (!profile.exists) {
        throw new HttpsError('permission-denied', 'PROFILE_REQUIRED');
      }
      if (!space.exists) {
        throw new HttpsError('not-found', 'MANUAL_LINK_SPACE_NOT_FOUND');
      }
      const ownerUid = space.data()?.ownerUid;
      if (typeof ownerUid !== 'string' || ownerUid.length === 0) {
        throw new HttpsError('failed-precondition', 'MANUAL_LINK_OWNER_INVALID');
      }
      if (!manual.exists) {
        throw new HttpsError('not-found', 'MANUAL_LINK_NOT_FOUND');
      }
      let mayClaim = member.exists;
      if (!mayClaim) {
        if (
          input.viaSessionId.length === 0
          || input.viaTicketId.length === 0
          || input.viaPid.length === 0
        ) {
          throw new HttpsError('permission-denied', 'MANUAL_LINK_NOT_AUTHORIZED');
        }
        const accessRef = db.doc(
          `sessions/${input.viaSessionId}/ticketAccess/${input.viaTicketId}_${uid}`,
        );
        const participantRef = db.doc(
          `sessions/${input.viaSessionId}/ticketParticipants/`
          + `${input.viaTicketId}_${input.viaPid}`,
        );
        const [access, participant] = await transaction.getAll(
          accessRef, participantRef,
        );
        const accessData = access.data() ?? {};
        const token = accessData.token;
        if (
          !access.exists
          || accessData.uid !== uid
          || accessData.ticketId !== input.viaTicketId
          || accessData.pid !== input.viaPid
          || accessData.manualId !== input.manualId
          || typeof token !== 'string'
          || token.length === 0
          || !participant.exists
          || participant.data()?.ticketId !== input.viaTicketId
          || participant.data()?.pid !== input.viaPid
        ) {
          throw new HttpsError('permission-denied', 'MANUAL_LINK_NOT_AUTHORIZED');
        }
        const ticketLink = await transaction.get(db.doc(`ticketLinks/${token}`));
        const linkData = ticketLink.data() ?? {};
        const rawExpiresAt = linkData.expiresAt;
        const expiresAt = timestampOf(rawExpiresAt);
        mayClaim = ticketLink.exists
          && linkData.status === 'active'
          && (rawExpiresAt == null
            || (expiresAt !== null && expiresAt.toMillis() > Date.now()))
          && linkData.sessionId === input.viaSessionId
          && linkData.ticketId === input.viaTicketId
          && linkData.targetPid === input.viaPid
          && linkData.targetManualId === input.manualId;
      }
      if (!mayClaim) {
        throw new HttpsError('permission-denied', 'MANUAL_LINK_NOT_AUTHORIZED');
      }

      const current = existing.data();
      if (existing.exists) {
        switch (current?.status) {
          case 'pending': return { action: 'pending' };
          case 'accepted': return { action: 'accepted' };
          case 'rejected': return { action: 'rejected' };
          default: return { action: 'terminal' };
        }
      }
      if (manual.data()?.linkedUid != null) {
        throw new HttpsError('failed-precondition', 'MANUAL_LINK_ALREADY_LINKED');
      }
      if (identity.exists) {
        throw new HttpsError('failed-precondition', 'MANUAL_LINK_IDENTITY_USED');
      }
      transaction.create(requestRef, {
        manualId: input.manualId,
        uid,
        displayName: input.displayName,
        spaceOwnerUid: ownerUid,
        ...(input.viaSessionId ? { viaSessionId: input.viaSessionId } : {}),
        ...(input.viaTicketId ? { viaTicketId: input.viaTicketId } : {}),
        ...(input.viaPid ? { viaPid: input.viaPid } : {}),
        status: 'pending',
        attempt: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        schemaVersion: 1,
      });
      return { action: 'created' };
    },
  );
  return decision;
});

const retryCooldownActive = (data: Record<string, unknown>, now: Timestamp) => {
  const requestedAt = timestampOf(data.linkRetryRequestedAt);
  return requestedAt !== null
    && now.toMillis() - requestedAt.toMillis() < RETRY_COOLDOWN_MS;
};

const retryResult = (
  status: LinkStatus,
  action: ManualLinkRetryAction,
): { status: LinkStatus; action: ManualLinkRetryAction } => ({ status, action });

/**
 * Solicita/repara la propagación de un vínculo ya aprobado.
 *
 * La Function adquiere directamente la reclamación para que su escritura de
 * `processing` no dispare una segunda propagación desde el trigger. El trigger
 * sigue siendo la ruta de alta inicial y conserva su protocolo de carrera.
 */
export const retryManualLinkPropagation = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
  }
  const { spaceId, manualId } = parseRetryInput(request.data);
  const requesterUid = request.auth.uid;
  const db = getFirestore();
  const spaceRef = db.doc(`spaces/${spaceId}`);
  const manualRef = manualLinkRef(spaceId, manualId);
  const now = Timestamp.now();

  const decision = await db.runTransaction(async (transaction) => {
    const [space, manual] = await transaction.getAll(spaceRef, manualRef);
    if (!space.exists) {
      throw new HttpsError('not-found', 'MANUAL_LINK_SPACE_NOT_FOUND');
    }
    if (!manual.exists) {
      throw new HttpsError('not-found', 'MANUAL_LINK_NOT_FOUND');
    }
    const spaceData = space.data() ?? {};
    const data = manual.data() ?? {};
    const linkedUid = data.linkedUid;
    if (typeof linkedUid !== 'string' || linkedUid.length === 0) {
      throw new HttpsError('failed-precondition', 'MANUAL_LINK_NOT_LINKED');
    }
    if (spaceData.ownerUid !== requesterUid && linkedUid !== requesterUid) {
      throw new HttpsError('permission-denied', 'MANUAL_LINK_NOT_AUTHORIZED');
    }

    const status = data.linkStatus as LinkStatus | undefined;
    if (status === 'active') return retryResult('active', 'active');

    if (status === 'processing') {
      const processingAt = timestampOf(data.linkProcessingAt);
      const claimId = data.linkClaimId;
      if (!processingAt || typeof claimId !== 'string' || claimId.length === 0) {
        return retryResult('processing', 'unclassifiable');
      }
      const age = now.toMillis() - processingAt.toMillis();
      if (age < PROCESSING_LEASE_MS) {
        return retryResult('processing', 'in-progress');
      }
      if (retryCooldownActive(data, now)) {
        return retryResult('processing', 'cooldown');
      }
      const acquired = claimUpdate(
        transaction,
        manualRef,
        data,
        'retry',
        requesterUid,
      );
      return { ...retryResult('processing', 'claimed'), claim: acquired };
    }

    if (status === 'failed') {
      if (retryCooldownActive(data, now)) {
        return retryResult('failed', 'cooldown');
      }
      const acquired = claimUpdate(
        transaction,
        manualRef,
        data,
        'retry',
        requesterUid,
      );
      return { ...retryResult('processing', 'claimed'), claim: acquired };
    }

    if (status === undefined) {
      const acquired = claimUpdate(
        transaction,
        manualRef,
        data,
        'initial',
        requesterUid,
      );
      return { ...retryResult('processing', 'claimed'), claim: acquired };
    }

    throw new HttpsError('failed-precondition', 'MANUAL_LINK_STATUS_INVALID');
  });

  if (!('claim' in decision) || !decision.claim) return decision;
  const result = await propagateClaimedManualLink(
    spaceId,
    manualId,
    decision.claim.linkedUid,
    decision.claim.claimId,
  );
  return {
    status: result.status,
    action: 'claimed' as const,
    sessions: result.sessions,
    ...(result.reason ? { reason: result.reason } : {}),
  };
});

/**
 * Dispara la propagación cuando `linkedUid` pasa de ausente a presente.
 *
 * Solo esa transición y el camino legado `failed -> processing` conservan
 * entrada para el trigger. La escritura `processing` del callable no lleva
 * `linkError` y el vínculo ya existía, así que se filtra y no duplica el
 * worker. Renombrar el manual, o cualquier escritura terminal posterior,
 * tampoco vuelve a entrar.
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
  const acquired = await acquireManualLinkPropagation(spaceId, manualId, claim);
  if (!acquired) return;
  await propagateClaimedManualLink(
    spaceId,
    manualId,
    acquired.linkedUid,
    acquired.claimId,
  );
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
