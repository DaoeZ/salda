import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

export default defineConfig({
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
});
