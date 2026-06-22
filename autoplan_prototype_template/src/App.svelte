<script>
  const modules = import.meta.glob('./prototypes/*.svelte', { eager: true })
  const prototypes = Object.entries(modules).map(([path, mod]) => ({
    name: path.replace('./prototypes/', '').replace('.svelte', ''),
    component: mod.default,
  }))

  let path = $state(location.pathname)
  let route = $derived(path.replace(/^\//, ''))
  let current = $derived(prototypes.find(p => p.name === route) ?? null)

  function navigate(name) {
    history.pushState({}, '', name ? `/${name}` : '/')
    path = location.pathname
  }

  $effect(() => {
    const onpop = () => { path = location.pathname }
    window.addEventListener('popstate', onpop)
    return () => window.removeEventListener('popstate', onpop)
  })
</script>

<div class="min-h-screen">
  {#if route === ''}
    <div class="p-6">
      {#if prototypes.length === 0}
        <p class="text-sm text-gray-400">No prototypes yet.<br/>Add .svelte files to src/prototypes/</p>
      {:else}
        <ul class="space-y-2">
          {#each prototypes as p}
            <li>
              <a
                href="/{p.name}"
                class="text-blue-600 hover:underline"
                onclick={(e) => { e.preventDefault(); navigate(p.name) }}
              >{p.name}</a>
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {:else if current}
    <current.component />
  {:else}
    <div class="p-6">
      <p class="mb-2 text-gray-700">Prototype "{route}" not found.</p>
      <a href="/" class="text-blue-600 hover:underline" onclick={(e) => { e.preventDefault(); navigate('') }}>Back to index</a>
    </div>
  {/if}
</div>
