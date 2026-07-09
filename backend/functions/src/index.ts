/**
 * Cloud Functions v2 — región europe-west1, minInstances 0, maxInstances 3
 * (límites de coste de la spec §12.4).
 *
 * Tres funciones y solo tres (spec §12.2), implementadas en M3:
 *  - recompute: calculadora autoritativa de totales/balances/liquidaciones.
 *    Motor TS validado contra los mismos vectores dorados que packages/domain.
 *  - notify:    FCM al anfitrión en pending→marked y "todos pagados".
 *  - cleanup:   borrado en cascada (subcolecciones + imágenes de Storage).
 *
 * M0: sin funciones desplegables todavía; este módulo compila vacío.
 */
import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({
  region: 'europe-west1',
  memory: '256MiB',
  minInstances: 0,
  maxInstances: 3,
});
