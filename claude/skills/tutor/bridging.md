# Bridging from a known domain

The fastest way to teach an experienced developer a new stack is to map new concepts onto ones they already own. Elicit their background first ("what do you reach for in your day job?"), then translate. Bridges are scaffolding — name where the analogy *breaks*, or they'll over-apply it.

## Frontend (React/Svelte/Vue) → SwiftUI

The mental models line up unusually well; lean on this hard.

| They know | SwiftUI equivalent | Where the analogy breaks |
|---|---|---|
| Component | `View` struct | Views are cheap value types, recreated constantly; don't store expensive state in them |
| `useState` / `$state` / `ref` | `@State` | `@State` must be `private` and lives with the view; SwiftUI owns the storage, not the struct |
| Props | `let` constants passed to the view's init | Immutable by default; a mutable binding needs `@Binding` |
| Two-way binding (`bind:value`) | `@Binding` / `$value` | The `$` prefix means "the binding to", not "the value" — trips people up |
| Derived / computed | a plain `var` computed property, or `@State` + reaction | No memoization by default like `$derived` |
| Context / stores / signals | `@Observable` model + `@Environment` | Reference type (`class`), not a value struct |
| Re-render on state change | View re-`body` on `@State` change | Diffing is by identity + structure; `id:` matters in lists |
| Conditional rendering (`{#if}`) | `if` inside `@ViewBuilder` body | Can't put arbitrary statements in a body — it's a result builder, not a function |
| `.map()` to a list | `ForEach` | Needs stable `id` |
| CSS / class props | View modifiers (`.padding()`, `.disabled()`) | Order matters — modifiers wrap, they don't merge like CSS |
| Disabled/locked UI state | `.disabled(condition)` + styling | — |

Key reframes worth stating out loud:
- **The view is a description, not the thing.** Like JSX, `body` describes what should exist for the current state; the framework reconciles. They already believe this from React — say so.
- **Value types (`struct`) vs reference types (`class`)** is the big new axis frontend devs lack. Views and most models are structs (copied); observable shared state is a class (referenced). This maps loosely onto "props are copied, stores are shared."
- **The compiler is strict and your friend.** Coming from JS/TS, the exhaustiveness (enums, optionals, `switch`) feels heavy but eliminates a class of runtime bugs they're used to chasing.

## Non-linear config with locked sections (the Stage F shape)

A useful teaching target because it exercises real state modeling, not just layout. Concepts it forces the learner to confront:

- **Modeling sections as data** (an `enum` of cases, or a struct list) rather than hardcoded views — the frontend instinct is often to hardcode; push them toward data-driven.
- **Derived lock state**: a section is locked when its prerequisites aren't met. This is a *computed* property of current state, not a stored flag to keep in sync (a classic frontend bug: duplicated derived state). Great place to teach "single source of truth."
- **Selection as state**: which section is shown is `@State`; navigation is just changing that value — no navigation stack, unlike a wizard. Contrast with a wizard's linear `currentStep + 1`.
- **`.disabled()` + affordance**: locked sections stay visible but non-interactive, so the user sees the whole map. Different from a wizard hiding future steps.

Let the learner discover the "derive lock state, don't store it" lesson by first storing it and hitting the sync bug — that mistake teaches more than being told.
