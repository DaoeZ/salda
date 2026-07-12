<script lang="ts">
  import { parseShareLink } from './lib/link';
  import { guest } from './lib/session.svelte';
  import ErrorView from './views/ErrorView.svelte';
  import PickItems from './views/PickItems.svelte';
  import Summary from './views/Summary.svelte';
  import TicketView from './views/TicketView.svelte';
  import WhoAreYou from './views/WhoAreYou.svelte';

  const link = parseShareLink(location.pathname, location.hash);
  let screen = $state<'summary' | 'pick' | 'ticket'>('summary');

  if (link) {
    void guest.connect(link);
  }
</script>

<main>
  {#if !link || guest.phase === 'invalid'}
    <ErrorView />
  {:else if guest.phase === 'connecting' || !guest.session}
    <!-- Skeleton, nunca spinner a pantalla completa (spec §3.8) -->
    <div class="stack" aria-busy="true" aria-label="Cargando">
      <div class="skeleton" style="height: 96px"></div>
      <div class="skeleton" style="height: 200px"></div>
      <div class="skeleton" style="height: 140px"></div>
    </div>
  {:else if !guest.myPid}
    <WhoAreYou />
  {:else if screen === 'pick'}
    <PickItems onback={() => (screen = 'summary')} />
  {:else if screen === 'ticket'}
    <TicketView onback={() => (screen = 'summary')} />
  {:else}
    <Summary
      onpick={() => (screen = 'pick')}
      onticket={() => (screen = 'ticket')}
    />
  {/if}
</main>

<style>
  main {
    max-width: 480px;
    margin: 0 auto;
    padding: var(--space-lg);
    padding-bottom: var(--space-xxl);
  }
  .stack {
    display: grid;
    gap: var(--space-md);
    margin-top: var(--space-lg);
  }
</style>
