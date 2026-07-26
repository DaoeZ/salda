/**
 * Infraestructura de pruebas INTEGRADAS: Functions reales contra el emulador
 * de Firestore, con Admin SDK.
 *
 * Por qué hacía falta. Hasta ahora `recompute` solo se probaba a través de su
 * función pura (`computeAggregates`) con datos inyectados a mano. Eso
 * demuestra el cálculo, pero NO que el flujo real produzca esos datos — y
 * justo ahí se escondía C1: aprobar una vinculación no disparaba nada, así
 * que el alias nunca llegaba a `computeAggregates` en producción y las
 * pruebas puras seguían en verde.
 *
 * Cómo se ejecuta:
 *   firebase emulators:exec --only firestore --project demo-salda \
 *     "npm --prefix backend/functions run test:integration"
 *
 * El emulador se detecta por FIRESTORE_EMULATOR_HOST, que `emulators:exec`
 * exporta. Sin esa variable las pruebas se saltan en vez de tocar un proyecto
 * real: una prueba integrada jamás debe poder escribir en salda-dev.
 */
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

export const emulatorAvailable = (): boolean =>
  Boolean(process.env.FIRESTORE_EMULATOR_HOST);

export const PROJECT_ID = 'demo-salda';

/**
 * App POR DEFECTO a propósito: el código de producción llama a
 * `getFirestore()` sin argumentos, así que una app con nombre haría que las
 * pruebas escribieran en una instancia distinta de la que usa la Function.
 */
export function db(): Firestore {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

export async function disposeApp(): Promise<void> {
  // La app por defecto se reutiliza durante toda la suite; cerrarla rompería
  // las pruebas siguientes del mismo proceso.
}

/** Borra por completo el estado entre pruebas, vía API del emulador. */
export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!response.ok) {
    throw new Error(`No se pudo limpiar el emulador: ${response.status}`);
  }
}

/**
 * Espera a que se cumpla una CONDICIÓN verificable, sondeando con un plazo
 * acotado. No es un sleep fijo: si la condición ya se cumple, vuelve de
 * inmediato; y el plazo solo existe para que un fallo se manifieste como tal
 * en vez de colgar la suite.
 */
export async function waitFor(
  description: string,
  condition: () => Promise<boolean>,
  { timeoutMs = 15000, intervalMs = 100 } = {},
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (await condition()) return;
    if (Date.now() > deadline) {
      throw new Error(`Tiempo agotado esperando: ${description}`);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}
