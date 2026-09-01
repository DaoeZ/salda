<script lang="ts">
  import {
    myUnits,
    needsShareConfirmation,
    otherConsumers,
    unitConsumers,
    unitIsPickedBy,
    unitsForQuantity,
    usesUnitModel,
  } from '../lib/assignment';
  import { formatCents } from '../lib/money';
  import { guest, type LineInfo } from '../lib/session.svelte';

  let { onback }: { onback: () => void } = $props();

  void guest.loadTickets();

  // Diálogo "¿compartir?" cuando pulso un producto que ya cogió otra
  // persona. `target` son las unidades que quedarán reclamadas al aceptar.
  let sharePrompt = $state<{
    line: LineInfo;
    names: string[];
    target: number;
    unit?: number;
  } | null>(null);

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

  function mine(line: LineInfo): number {
    return myUnits(line.assignment, guest.myPid ?? '');
  }

  function consumersOf(line: LineInfo, unit: number): string[] {
    return unitConsumers(line.assignment, unit);
  }

  function unitNames(line: LineInfo, unit: number): string[] {
    return consumersOf(line, unit).map((pid) => names.get(pid) ?? '?');
  }

  function unitMine(line: LineInfo, unit: number): boolean {
    return unitIsPickedBy(line.assignment, unit, guest.myPid ?? '');
  }

  /** Fija mis unidades; al SUMARME a algo de otros, pregunta antes. */
  async function requestUnits(line: LineInfo, target: number) {
    if (!guest.open || !guest.myPid) return;
    if (
      target > 0 &&
      mine(line) === 0 &&
      needsShareConfirmation(line.assignment, guest.myPid)
    ) {
      sharePrompt = { line, names: others(line), target };
      return;
    }
    await guest.setLineUnits(line, target);
  }

  async function tap(line: LineInfo) {
    await requestUnits(line, mine(line) > 0 ? 0 : 1);
  }

  async function requestUnit(line: LineInfo, unit: number) {
    if (!guest.open || !guest.myPid) return;
    const selected = unitMine(line, unit);
    const otherNames = unitNames(line, unit).filter(
      (_, index) => consumersOf(line, unit)[index] !== guest.myPid,
    );
    if (!selected && otherNames.length > 0) {
      sharePrompt = { line, names: otherNames, target: 1, unit };
      return;
    }
    await guest.setLineUnit(line, unit, !selected);
  }

  async function confirmShare() {
    const prompt = sharePrompt;
    sharePrompt = null;
    if (!prompt) return;
    if (prompt.unit !== undefined) {
      await guest.setLineUnit(prompt.line, prompt.unit, true);
    } else {
      await guest.setLineUnits(prompt.line, prompt.target);
    }
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
    se divide solo. En los productos con varias unidades, elige cuántas son
    tuyas con + y −.
  </p>
</header>

<!-- A5: un rechazo de las reglas tiene que verse. Antes la casilla revertía
     sola y nadie explicaba por qué. -->
{#if guest.error}
  <p class="write-error" role="alert">{guest.error}</p>
{/if}

{#each guest.tickets.filter((t) => t.pickable) as ticket (ticket.id)}
  <section>
    <h2>{ticket.merchantName}</h2>
    <div class="lines">
      {#each ticket.lines as line (line.id)}
        {@const units = unitsForQuantity(line.quantityMilli)}
        {@const myN = mine(line)}
        {@const shared = others(line)}
        {#if usesUnitModel(line.assignment)}
          <div class="card unit-line">
            <div class="line-heading">
              <span class="info">
                <span class="name">{units > 1 ? `${units}× ` : ''}{line.name}</span>
                <span class="muted small">
                  Elige unidades concretas. Si otra persona marca la misma, se comparte.
                </span>
              </span>
              <span class="money">{formatCents(line.totalPrice)}</span>
            </div>
            <div class:many={units > 12} class="unit-grid" role="group" aria-label={`Unidades de ${line.name}`}>
              {#each Array.from({ length: units }, (_, i) => i) as unit (unit)}
                {@const selected = unitMine(line, unit)}
                {@const consumers = unitNames(line, unit)}
                <button
                  class="unit"
                  class:selected
                  aria-pressed={selected}
                  disabled={!guest.open}
                  onclick={() => requestUnit(line, unit)}
                >
                  <strong>Unidad {unit + 1}</strong>
                  <span class="small">
                    {consumers.length > 0 ? shareNames(consumers) : 'Sin reclamar'}
                  </span>
                </button>
              {/each}
            </div>
          </div>
        {:else if units === 1}
          <button
            class="card line"
            class:mine={myN > 0}
            aria-pressed={myN > 0}
            disabled={!guest.open}
            onclick={() => tap(line)}
          >
            <span class="check" aria-hidden="true">{myN > 0 ? '✓' : ''}</span>
            <span class="info">
              <span class="name">{line.name}</span>
              {#if shared.length > 0}
                <span class="muted small">
                  {myN > 0 ? 'compartido con' : 'lo tiene'}
                  {shareNames(shared)}
                </span>
              {/if}
            </span>
            <span class="money">{formatCents(line.totalPrice)}</span>
          </button>
        {:else}
          <!-- Histórico P2.1: se muestra sin reinterpretar. Solo el owner
               puede convertirlo porque los pesos no identifican unidades. -->
          <div class="card line multi legacy" class:mine={myN > 0}>
            <span class="check" aria-hidden="true">{myN > 0 ? '✓' : ''}</span>
            <span class="info">
              <span class="name">{units}× {line.name}</span>
              {#if shared.length > 0}
                <span class="muted small">
                  {myN > 0 ? 'compartido con' : 'lo tiene'}
                  {shareNames(shared)}
                </span>
              {/if}
              <span class="muted small">Reparto anterior · el creador debe actualizarlo por unidades</span>
            </span>
            <span class="money">{formatCents(line.totalPrice)}</span>
          </div>
        {/if}
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
  .write-error {
    margin: 0 0 var(--space-md);
    padding: var(--space-md);
    border-radius: var(--radius-card);
    background: var(--color-negative-muted);
    color: var(--color-negative);
    font-size: 14px;
    line-height: 1.4;
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
  .unit-line {
    padding: var(--space-md) var(--space-lg);
  }
  .line-heading {
    display: flex;
    align-items: start;
    gap: var(--space-md);
    margin-bottom: var(--space-sm);
  }
  .unit-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(112px, 1fr));
    gap: var(--space-xs);
  }
  .unit-grid.many {
    grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
    max-height: 260px;
    overflow-y: auto;
    padding-right: 2px;
  }
  .unit {
    min-width: 0;
    min-height: 52px;
    display: grid;
    gap: 2px;
    text-align: left;
    padding: var(--space-sm);
    border: 1px solid var(--outline);
    border-radius: var(--radius-control);
    background: var(--surface);
    color: var(--on-surface);
  }
  .unit.selected {
    border-color: var(--primary);
    background: var(--primary-container);
    color: var(--on-primary-container);
  }
  .unit span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
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
