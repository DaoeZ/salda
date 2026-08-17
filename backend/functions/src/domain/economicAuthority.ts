/**
 * Autoridad económica sobre un actor — espejo exacto de
 * packages/domain/lib/src/identity/economic_authority.dart (ADR-038).
 *
 * El receptor del dinero es quien confirma que lo ha recibido. Ser
 * administrador o propietario de un espacio NO otorga esa capacidad sobre una
 * cuenta registrada; solo permite representar a un participante MANUAL, que
 * por definición no tiene forma de confirmar nada. Vincular ese manual a una
 * cuenta (ADR-037) termina la representación sin revocar nada.
 */
import { isAccountActor } from './economicActor.js';

export type EconomicActingRole = 'self' | 'representative' | 'none';

export function economicActingRole(params: {
  actor: string;
  viewerUid: string;
  viewerIsSpaceAdmin?: boolean;
  linkedUid?: string | null;
}): EconomicActingRole {
  const { actor, viewerUid } = params;
  if (!actor || !viewerUid) return 'none';

  // Una cuenta responde siempre por sí misma: aquí se cierra la puerta a que
  // un administrador toque el saldo de un usuario registrado.
  if (isAccountActor(actor)) return actor === viewerUid ? 'self' : 'none';

  const linkedUid = params.linkedUid;
  if (linkedUid) return linkedUid === viewerUid ? 'self' : 'none';

  return params.viewerIsSpaceAdmin === true ? 'representative' : 'none';
}

export const canConfirmReceipt = (params: {
  creditorActor: string;
  viewerUid: string;
  viewerIsSpaceAdmin?: boolean;
  linkedUid?: string | null;
}): boolean =>
  economicActingRole({
    actor: params.creditorActor,
    viewerUid: params.viewerUid,
    viewerIsSpaceAdmin: params.viewerIsSpaceAdmin,
    linkedUid: params.linkedUid,
  }) !== 'none';
