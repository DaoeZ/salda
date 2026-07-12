<script lang="ts">
  import { guest } from '../lib/session.svelte';

  let taken = $state<string | null>(null);

  async function pick(pid: string) {
    taken = null;
    if ((await guest.claim(pid)) === 'taken') taken = pid;
  }
</script>

<header>
  <p class="muted">{guest.session?.name}</p>
  <h1>¿Quién eres?</h1>
</header>

<div class="people">
  {#each guest.participants as person (person.id)}
    {@const busy = person.claimedByDevice !== '' && !person.isOwner}
    <button
      class="card person"
      onclick={() => pick(person.id)}
      disabled={person.isOwner}
    >
      <span class="avatar" aria-hidden="true">{person.name.at(0) ?? '?'}</span>
      <span class="name">{person.name}</span>
      {#if person.isOwner}
        <span class="chip">anfitrión</span>
      {:else if busy}
        <span class="chip">en otro móvil</span>
      {/if}
    </button>
    {#if taken === person.id}
      <p class="taken" role="alert">
        Alguien ya eligió este nombre en otro dispositivo. Si eres tú,
        pide al anfitrión que lo libere.
      </p>
    {/if}
  {/each}
</div>

<style>
  header {
    margin: var(--space-lg) 0;
  }
  h1 {
    font-size: 26px;
    margin: 4px 0 0;
  }
  header p {
    margin: 0;
  }
  .people {
    display: grid;
    gap: var(--space-sm);
  }
  .person {
    display: flex;
    align-items: center;
    gap: var(--space-md);
    text-align: left;
    min-height: 64px;
    width: 100%;
  }
  .name {
    font-size: 17px;
    font-weight: 500;
    flex: 1;
  }
  .taken {
    color: var(--error);
    font-size: 13px;
    margin: 4px var(--space-sm);
  }
</style>
