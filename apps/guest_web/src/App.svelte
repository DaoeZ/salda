<script lang="ts">
  import { BRAND } from './lib/brand';

  // M0: placeholder. Las vistas reales (¿Quién eres? / Mi resumen / Mis
  // productos / Ticket) se implementan en M4 sobre Firestore en tiempo real.
</script>

<main>
  <h1>{BRAND.appName}</h1>
  <p>{BRAND.tagline}</p>
  <p class="hint">Web de invitados — en construcción (M4).</p>
</main>

<style>
  main {
    max-width: 480px;
    margin: 0 auto;
    padding: var(--space-lg);
    text-align: center;
  }
  h1 {
    color: var(--color-seed);
  }
  .hint {
    color: var(--color-settlement-pending);
    font-size: 14px;
  }
</style>
