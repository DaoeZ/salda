<script lang="ts">
  import {
    needsShareConfirmation,
    otherConsumers,
  } from '../lib/assignment';
  import { formatCents } from '../lib/money';
  import { guest, type LineInfo } from '../lib/session.svelte';

  let { onback }: { onback: () => void } = $props();

  void guest.loadTickets();

  // Diálogo "¿compartir?" cuando pulso un producto que ya cogió otra persona.
  let sharePrompt = $state<{ line: LineInfo; names: string[] } | null>(null);

  const names = $derived(
    new Map(guest.participants.map((p) => [p.id, p.name])),
  );
  const myConsumed = $derived(
    guest.myPid ? (guest.session?.balances[guest.myPid]?.consumed ?? 0) : 0,
  );

  function others(line: LineInfo) {
    return otherConsumers(line.assignment, guest.myPid ?? '').map(
      (pid) => names.get(pid) ?? '?',
    );
  }

  async function tap(line: LineInfo) {
    if (!guest.open || !guest.myPid) return;
    // Quitármela nunca pregunta; sumarme a algo que ya cogió otro, sí.
    if (guest.isMine(line)) {
      await guest.toggleLine(line);
    } else if (needsShareConfirmation(line.assignment, guest.myPid)) {
      sharePrompt = { line, names: others(line) };
    } else {
      await guest.toggleLine(line);
    }
  }

  async function confirmShare() {
    const prompt = sharePrompt;
    sharePrompt = null;
    if (prompt) await guest.toggleLine(prompt.line);
  }

  function shareNames(list: string[]): string {
    if (list.length === 1) return list[0];
    return `${list.slice(0, -1).join(', ')} y ${list[list.length - 1]}`;
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
          onclick={() => tap(line)}
        >
          <span class="check" aria-hidden="true">{mine ? '✓' : ''}</span>
          <span class="info">
            <span class="name">{line.name}</span>
            {#if shared.length > 0}
              <span class="muted small">
                {mine ? 'compartido con' : 'lo tiene'}
                {shareNames(shared)}
              </span>
            {/if}
          </span>
          <span class="money">{formatCents(line.totalPrice)}</span>
        </button>
      {/each}
    </div>
  </section>
{/each}

{#if sharePrompt}
  <div
    class="overlay"
    role="button"
    tabindex="-1"
    onclick={() => (sharePrompt = null)}
    onkeydown={(e) => e.key === 'Escape' && (sharePrompt = null)}
  >
    <div
      class="card dialog"
      role="dialog"
      tabindex="-1"
      aria-modal="true"
      aria-labelledby="share-title"
      onclick={(e) => e.stopPropagation()}
      onkeydown={() => {}}
    >
      <h2 id="share-title">{shareNames(sharePrompt.names)} ya lo ha seleccionado</h2>
      <p class="muted">¿Queréis compartirlo? El precio se dividirá entre vosotros.</p>
      <div class="dialog-actions">
        <button class="btn-text" onclick={() => (sharePrompt = null)}>Cancelar</button>
        <button class="btn-primary" onclick={confirmShare}>Compartir</button>
      </div>
    </div>
  </div>
{/if}

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
  .overlay {
    position: fixed;
    inset: 0;
    background: rgb(0 0 0 / 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-lg);
    z-index: 10;
    animation: fade var(--duration-enter) var(--easing-emphasized);
  }
  .dialog {
    width: 100%;
    max-width: 360px;
    cursor: default;
    animation: pop var(--duration-enter) var(--easing-emphasized);
  }
  .dialog h2 {
    font-size: 19px;
    margin: 0 0 var(--space-sm);
  }
  .dialog p {
    margin: 0;
    line-height: 1.4;
  }
  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-sm);
    margin-top: var(--space-lg);
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @keyframes pop {
    from {
      opacity: 0;
      transform: scale(0.96);
    }
  }
</style>
