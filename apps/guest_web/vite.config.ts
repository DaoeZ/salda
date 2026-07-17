import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, __dirname, 'VITE_FB_');
  if (mode === 'salda-dev' && env.VITE_FB_PROJECT_ID !== 'salda-dev') {
    throw new Error('El build salda-dev debe usar el proyecto salda-dev');
  }
  if (
    mode === 'production' &&
    (env.VITE_FB_PROJECT_ID !== 'salda-prod' ||
      env.VITE_FB_AUTH_DOMAIN?.includes('salda-dev'))
  ) {
    throw new Error(
      'El build de producción requiere configuración explícita de salda-prod',
    );
  }

  return {
    plugins: [svelte()],
    build: {
    // El SDK de Firebase va en su propio chunk (cacheable entre deploys).
    rollupOptions: {
      output: {
        manualChunks: (id) =>
          id.includes('node_modules/@firebase') ||
          id.includes('node_modules/firebase')
            ? 'firebase'
            : undefined,
      },
    },
    // El presupuesto REAL es de transferencia (gzip) y lo hace cumplir
    // scripts/check-size.mjs en CI; este aviso de Vite mide chunks sin
    // comprimir y el SDK de Firestore lo supera por naturaleza.
    chunkSizeWarningLimit: 900,
    },
  };
});
