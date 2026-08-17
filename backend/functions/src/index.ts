/**
 * Cloud Functions v2 — región europe-west1, minInstances 0, maxInstances 3
 * (techos de coste de la spec §12.4: NO subirlos sin consultar al usuario).
 *
 * Tres funciones conceptuales (spec §12.2):
 *  - recompute: calculadora autoritativa (3 triggers → mismo recálculo).
 *  - notify:    FCM al anfitrión.
 *  - cleanup:   borrado en cascada de sesiones.
 * Los agregados que escribe recompute son solo-lectura para los clientes
 * (lo garantizan las reglas); el Admin SDK las ignora por diseño.
 */
import { initializeApp } from 'firebase-admin/app';
import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({
  region: 'europe-west1',
  memory: '256MiB',
  minInstances: 0,
  maxInstances: 3,
});

initializeApp();

export {
  recomputeOnLine,
  recomputeOnEconomicPayment,
  recomputeOnParticipant,
  recomputeOnSettlement,
  recomputeOnTicket,
  rebuildMyEconomicRelations,
} from './recompute.js';
export { notifyOnSettlement } from './notify.js';
export { cleanupOnSessionDelete } from './cleanup.js';
export {
  createEconomicPayment,
  resolveEconomicPayment,
  settleEconomicEntries,
} from './economicPayments.js';
export {
  activityOnSpace,
  activityOnSpaceMember,
  activityOnSpaceInvite,
  activityOnTicketWrite,
  activityOnSettlementWrite,
  activityOnEconomicPaymentWrite,
} from './activity.js';
// Propagación de vinculaciones MANUAL↔identidad (ADR-037, C1).
export {
  propagateOnManualLink,
  requestManualLink,
  retryManualLinkPropagation,
} from './manualLink.js';
