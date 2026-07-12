/**
 * Inicialización de Firebase (JS modular, tree-shaken).
 *
 * Config por variables VITE_FB_* con fallback al proyecto demo de los
 * emuladores. En `npm run dev` se conecta SIEMPRE a la Emulator Suite;
 * el build de producción usará las variables reales cuando existan los
 * proyectos (CLAUDE.md · próximos pasos).
 */
import { initializeApp } from 'firebase/app';
import {
  connectAuthEmulator,
  getAuth,
  signInAnonymously,
  type User,
} from 'firebase/auth';
import {
  connectFirestoreEmulator,
  getFirestore,
} from 'firebase/firestore';

const env = import.meta.env;

const app = initializeApp({
  apiKey: env.VITE_FB_API_KEY ?? 'demo-api-key',
  authDomain: env.VITE_FB_AUTH_DOMAIN ?? 'demo-salda.firebaseapp.com',
  projectId: env.VITE_FB_PROJECT_ID ?? 'demo-salda',
  appId: env.VITE_FB_APP_ID ?? '1:000000000000:web:demo',
});

export const auth = getAuth(app);
export const db = getFirestore(app);

if (env.DEV) {
  connectAuthEmulator(auth, 'http://localhost:9099', {
    disableWarnings: true,
  });
  connectFirestoreEmulator(db, 'localhost', 8080);
}

/** Sesión anónima del invitado (RF-04): transparente, sin pantallas. */
export async function ensureSignedIn(): Promise<User> {
  if (auth.currentUser) return auth.currentUser;
  const credential = await signInAnonymously(auth);
  return credential.user;
}
