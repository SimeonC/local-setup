<script>
  const modules = import.meta.glob('./prototypes/*.svelte', { eager: true })
  const prototypes = Object.entries(modules).map(([path, mod]) => ({
    name: path.replace('./prototypes/', '').replace('.svelte', ''),
    component: mod.default,
  }))

  let selected = $state(prototypes[0]?.name ?? null)
  let current = $derived(prototypes.find(p => p.name === selected) ?? null)
</script>

<div class="flex h-screen">
  <aside class="w-48 shrink-0 border-r bg-gray-50 p-4">
    <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">Prototypes</h2>
    {#if prototypes.length === 0}
      <p class="text-sm text-gray-400">No prototypes yet.<br/>Add .svelte files to src/prototypes/</p>
    {:else}
      <ul class="space-y-1">
        {#each prototypes as p}
          <li>
            <button
              class="w-full rounded px-2 py-1 text-left text-sm {selected === p.name ? 'bg-blue-100 text-blue-700 font-medium' : 'text-gray-700 hover:bg-gray-100'}"
              onclick={() => selected = p.name}
            >{p.name}</button>
          </li>
        {/each}
      </ul>
    {/if}
  </aside>
  <main class="flex-1 overflow-auto p-6">
    {#if current}
      <svelte:component this={current.component} />
    {:else}
      <div class="flex h-full items-center justify-center text-gray-400">
        Select a prototype from the sidebar
      </div>
    {/if}
  </main>
</div>
