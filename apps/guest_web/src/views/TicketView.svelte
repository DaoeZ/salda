<script lang="ts">
  import { formatCents } from '../lib/money';
  import { guest } from '../lib/session.svelte';

  let { onback }: { onback: () => void } = $props();

  void guest.loadTickets();

  function quantity(milli: number): string | null {
    if (milli === 1000) return null;
    return milli % 1000 === 0
      ? `${milli / 1000} ×`
      : `${(milli / 1000).toLocaleString('es-ES')} kg`;
  }
</script>

<header>
  <button class="btn-text" onclick={onback} aria-label="Volver">← Volver</button>
  <h1>Ticket completo</h1>
</header>

{#each guest.tickets as ticket (ticket.id)}
  <section class="card">
    <h2>{ticket.merchantName}</h2>
    <ul>
      {#each ticket.lines as line (line.id)}
        <li>
          <span class="name">
            {#if quantity(line.quantityMilli)}
              <span class="muted">{quantity(line.quantityMilli)}</span>
            {/if}
            {line.name}
          </span>
          <span class="money">{formatCents(line.totalPrice)}</span>
        </li>
      {/each}
    </ul>
    <div class="total">
      <span>Total</span>
      <span class="money">{formatCents(ticket.grandTotal)}</span>
    </div>
  </section>
{/each}

<style>
  header {
    margin: var(--space-md) 0 var(--space-lg);
  }
  header .btn-text {
    padding: 0;
    min-height: 40px;
  }
  h1 {
    font-size: 24px;
    margin: var(--space-xs) 0 0;
  }
  section {
    margin-bottom: var(--space-md);
  }
  h2 {
    font-size: 16px;
    margin: 0 0 var(--space-sm);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  li {
    display: flex;
    justify-content: space-between;
    gap: var(--space-md);
    padding: 6px 0;
    border-bottom: 1px solid var(--surface-high);
  }
  .name {
    flex: 1;
  }
  .total {
    display: flex;
    justify-content: space-between;
    padding-top: var(--space-md);
    font-weight: 600;
    font-size: 17px;
  }
</style>
