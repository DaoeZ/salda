<script lang="ts">
  import { formatCents } from '../lib/money';
  import { guest } from '../lib/session.svelte';

  let { onback }: { onback: () => void } = $props();

  void guest.loadTickets();

  const names = $derived(
    new Map(guest.participants.map((p) => [p.id, p.name])),
  );
  const myConsumed = $derived(
    guest.myPid ? (guest.session?.balances[guest.myPid]?.consumed ?? 0) : 0,
  );

  function others(line: { assignment?: { participants?: Record<string, number> } }) {
    return Object.keys(line.assignment?.participants ?? {})
      .filter((pid) => pid !== guest.myPid)
      .map((pid) => names.get(pid) ?? '?');
  }
</script>

<header>
  <button class="btn-text" onclick={onback} aria-label="Volver">← Volver</button>
  <h1>Tus productos</h1>
  <p class="muted">
    Marca lo que consumiste tú. Si algo era compartido, marcadlo cada uno y
    se divide solo.
  </p>
</header>

{#each guest.tickets.filter((t) => t.pickable) as ticket (ticket.id)}
  <section>
    <h2>{ticket.merchantName}</h2>
    <div class="lines">
      {#each ticket.lines as line (line.id)}
        {@const mine = guest.isMine(line)}
        {@const shared = others(line)}
        <button
          class="card line"
          class:mine
          aria-pressed={mine}
          disabled={!guest.open}
          onclick={() => guest.toggleLine(line)}
        >
          <span class="check" aria-hidden="true">{mine ? '✓' : ''}</span>
          <span class="info">
            <span class="name">{line.name}</span>
            {#if shared.length > 0}
              <span class="muted small">con {shared.join(', ')}</span>
            {/if}
          </span>
          <span class="money">{formatCents(line.totalPrice)}</span>
        </button>
      {/each}
    </div>
  </section>
{/each}

<footer class="card total">
  <span>Llevas marcado</span>
  <span class="money big">{formatCents(myConsumed)}</span>
  <p class="muted small">El importe se actualiza en unos segundos.</p>
</footer>

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
    margin: var(--space-xs) 0;
  }
  header p {
    margin: 0;
    line-height: 1.4;
  }
  h2 {
    font-size: 15px;
    color: var(--on-surface-variant);
    font-weight: 500;
    margin: var(--space-lg) 0 var(--space-sm);
  }
  .lines {
    display: grid;
    gap: var(--space-sm);
  }
  .line {
    display: flex;
    align-items: center;
    gap: var(--space-md);
    width: 100%;
    text-align: left;
    min-height: 56px;
    padding: var(--space-md) var(--space-lg);
  }
  .line.mine {
    border-color: var(--primary);
    background: var(--primary-container);
    color: var(--on-primary-container);
  }
  .check {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    border: 2px solid var(--outline);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    flex: none;
    transition: all var(--duration-toggle) var(--easing-emphasized);
  }
  .mine .check {
    background: var(--primary);
    border-color: var(--primary);
    color: var(--on-primary);
  }
  .info {
    flex: 1;
    display: grid;
  }
  .name {
    font-weight: 500;
  }
  .small {
    font-size: 12px;
  }
  .total {
    position: sticky;
    bottom: var(--space-md);
    margin-top: var(--space-lg);
    display: grid;
    grid-template-columns: 1fr auto;
    align-items: center;
    box-shadow: 0 4px 16px rgb(0 0 0 / 0.12);
  }
  .total .big {
    font-size: 22px;
  }
  .total p {
    grid-column: 1 / -1;
    margin: 4px 0 0;
  }
</style>
