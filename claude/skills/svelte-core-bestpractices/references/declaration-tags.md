---
title: Declaration tags ({let} / {const}) in templates
svelte_version: "5.56+"
---

## Syntax

```svelte
{let x = $state(0)}
{const label = $derived(`count: ${x}`)}
{let a = 1, b = $state(2)}
```

Tags can appear anywhere in the template (top level, inside `{#if}`, `{#each}`, etc.). They follow **block-level scoping** — the same rules as JavaScript `let`/`const`: visible from the point of declaration to the end of the enclosing block.

## Multiple declarators in one tag

```svelte
{let start = 0, end = $state(10)}
```

Later declarators in the same tag may reference earlier ones, matching JavaScript semantics.

## Duplicate names

Declaring the same name twice in the same scope is a **compile-time error** (mirrors JS `let`/`const` behaviour). Shadowing in a nested block is fine.

## When to use vs `{@const}`

| Need | Use |
|---|---|
| Non-reactive computed constant inside `{#each}` or `{#if}` | `{@const value = a + b}` |
| Reactive state scoped to a template block | `{let x = $state(0)}` |
| Reactive derived scoped to a template block | `{const y = $derived(x * 2)}` |

`{@const}` remains the idiomatic choice for non-reactive one-off computations to avoid the proxy overhead of `$state`.
