<script lang="ts">
  import { formatCents, formatCentsAbs } from '../lib/money';
  import {
    copyText,
    paypalUrl,
    prettyIban,
    revolutUrl,
  } from '../lib/payments';
  import { guest } from '../lib/session.svelte';

  let { onpick, onticket }: { onpick: () => void; onticket: () => void } =
    $props();

  let copied = $state('');

  const names = $derived(
    new Map(guest.participants.map((p) => [p.id, p.name])),
  );
  const mine = $derived(
    guest.settlements.filter((s) => s.from === guest.myPid),
  );
  const owedToMe = $derived(
    guest.settlements.filter(
      (s) => s.to === guest.myPid && s.state !== 'confirmed',
    ),
  );
  const iOweCents = $derived(
    mine
      .filter((s) => s.state !== 'confirmed')
      .reduce((a, s) => a + s.amount, 0),
  );
  const progress = $derived(
    guest.session && guest.session.totals.grandTotal > 0
      ? Math.min(
          1,
          guest.session.totals.settledConfirmed /
            guest.session.totals.grandTotal,
        )
      : 0,
  );
  const anyPickable = $derived(guest.tickets.some((t) => t.pickable));
  const methods = $derived(guest.session?.paymentMethods ?? {});

  // Los tickets se cargan ya en el resumen para saber si hay modo "lo suyo".
  void guest.loadTickets();

  async function copy(text: string, tag: string) {
    if (await copyText(text)) {
      copied = tag;
      setTimeout(() => (copied = ''), 2000);
    }
  }
</script>

<header>
  <p class="muted">{guest.session?.name}</p>
  <h1>Hola, {guest.me?.name} 👋</h1>
</header>

{#if !guest.open}
  <p class="chip closed">Cuenta cerrada · solo lectura</p>
{/if}

<section class="card hero" aria-live="polite">
  {#if iOweCents === 0}
    <p class="big">Estás en paz 🎉</p>
    <p class="muted">No debes nada en esta cuenta.</p>
  {:else}
    <p class="muted">Te toca pagar</p>
    <p class="big money">{formatCentsAbs(iOweCents)}</p>
  {/if}
</section>

{#each mine as settlement (settlement.id)}
  <section class="card pay">
    <div class="row">
      <span>
        A <strong>{names.get(settlement.to) ?? '—'}</strong>
      </span>
      <span class="money">{formatCents(settlement.amount)}</span>
    </div>

    {#if settlement.state === 'confirmed'}
      <p class="state ok">✓ Pago confirmado</p>
    {:else if settlement.state === 'marked'}
      <p class="state waiting">Avisaste de que pagaste · esperando confirmación</p>
    {:else}
      {#if methods.paypalLink}
        <a
          class="method"
          href={paypalUrl(methods.paypalLink, settlement.amount)}
          target="_blank"
          rel="noopener noreferrer">Pagar con PayPal</a
        >
      {/if}
      {#if methods.revolutTag}
        <a
          class="method"
          href={revolutUrl(methods.revolutTag, settlement.amount)}
          target="_blank"
          rel="noopener noreferrer">Pagar con Revolut</a
        >
      {/if}
      {#if methods.bizumPhone}
        <button
          class="method"
          onclick={() => copy(methods.bizumPhone!, `bizum-${settlement.id}`)}
        >
          Bizum al {methods.bizumPhone}
          {copied === `bizum-${settlement.id}` ? ' · copiado ✓' : ''}
        </button>
      {/if}
      {#if methods.iban}
        <button
          class="method"
          onclick={() => copy(methods.iban!, `iban-${settlement.id}`)}
        >
          {prettyIban(methods.iban)}
          {copied === `iban-${settlement.id}` ? ' · copiado ✓' : ''}
        </button>
      {/if}
      {#if guest.open}
        <button
          class="btn-primary paid"
          onclick={() => guest.markPaid(settlement.id)}
        >
          Ya he pagado
        </button>
      {/if}
    {/if}
  </section>
{/each}

{#if owedToMe.length > 0}
  <section class="card">
    <p class="muted small">Te deben</p>
    {#each owedToMe as settlement (settlement.id)}
      <div class="row">
        <span>{names.get(settlement.from) ?? '—'}</span>
        <span class="money">{formatCents(settlement.amount)}</span>
      </div>
    {/each}
  </section>
{/if}

<nav class="actions">
  {#if anyPickable && guest.open}
    <button class="btn-tonal" onclick={onpick}>Elegir mis productos</button>
  {/if}
  <button class="btn-text" onclick={onticket}>Ver el ticket</button>
</nav>

<section class="progress-block">
  <div
    class="track"
    role="progressbar"
    aria-label="Progreso de pagos del grupo"
    aria-valuenow={Math.round(progress * 100)}
    aria-valuemin="0"
    aria-valuemax="100"
  >
    <div class="fill" style="width: {progress * 100}%"></div>
  </div>
  <p class="muted small">
    {formatCents(guest.session?.totals.settledConfirmed ?? 0)} de
    {formatCents(guest.session?.totals.grandTotal ?? 0)} saldados
  </p>
</section>

<footer>
  <button class="btn-text small" onclick={() => guest.release()}>
    No soy {guest.me?.name}
  </button>
</footer>

<style>
  header {
    margin: var(--space-lg) 0;
  }
  h1 {
    font-size: 24px;
    margin: 4px 0 0;
  }
  header p {
    margin: 0;
  }
  section {
    margin-bottom: var(--space-md);
  }
  .hero {
    text-align: center;
  }
  .big {
    font-size: 40px;
    font-weight: 600;
    margin: 4px 0;
  }
  .hero .muted {
    margin: 0;
  }
  .row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--space-md);
    padding: 6px 0;
  }
  .state {
    font-size: 14px;
    margin: var(--space-sm) 0 0;
  }
  .state.ok {
    color: var(--primary);
    font-weight: 600;
  }
  .state.waiting {
    color: var(--on-surface-variant);
  }
  .method {
    display: block;
    width: 100%;
    margin-top: var(--space-sm);
    padding: 12px var(--space-lg);
    border-radius: var(--radius-field);
    background: var(--surface-high);
    text-align: center;
    text-decoration: none;
    color: inherit;
    font-weight: 500;
    border: none;
    cursor: pointer;
    font-size: 15px;
  }
  .paid {
    width: 100%;
    margin-top: var(--space-md);
  }
  .actions {
    display: grid;
    gap: var(--space-sm);
    margin: var(--space-lg) 0;
  }
  .closed {
    margin-bottom: var(--space-md);
  }
  .track {
    height: 6px;
    border-radius: 3px;
    background: var(--surface-high);
    overflow: hidden;
  }
  .fill {
    height: 100%;
    background: var(--primary);
    transition: width var(--duration-enter) var(--easing-emphasized);
  }
  .small {
    font-size: 13px;
  }
  .progress-block p {
    margin: var(--space-xs) 0 0;
  }
  footer {
    margin-top: var(--space-xl);
    text-align: center;
  }
</style>
