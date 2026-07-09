import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  build: {
    // Presupuesto de la spec (§5.2): bundle pequeño y carga < 1 s en 4G.
    // Si un cambio dispara el peso, este aviso lo delata en CI.
    chunkSizeWarningLimit: 300,
  },
});
