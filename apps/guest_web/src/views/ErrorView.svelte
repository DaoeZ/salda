<script lang="ts">
  import { BRAND } from '../lib/brand';
</script>

<div class="card center">
  <div class="emoji" aria-hidden="true">🧾</div>
  <h1>Este enlace no funciona</h1>
  <p class="muted">
    Puede que la cuenta se haya cerrado, que el enlace haya caducado o que
    esté incompleto. Pide a quien te invitó que te lo envíe otra vez desde
    {BRAND.appName}.
  </p>
</div>

<style>
  .center {
    margin-top: 15dvh;
    text-align: center;
  }
  .emoji {
    font-size: 48px;
  }
  h1 {
    font-size: 22px;
    margin: var(--space-md) 0 var(--space-sm);
  }
  p {
    margin: 0;
    line-height: 1.5;
  }
</style>
