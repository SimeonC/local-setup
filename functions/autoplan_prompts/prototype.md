## Prototype phase
- Spec is ONLY the plan at $PLAN_FILE. Ignore `next:`, earlier chain links, and sibling plans.
- Purpose: build small throwaway prototypes to settle UI direction interactively with the user. Do NOT implement the real feature — that's implement's job.
- A Vite + Svelte + Tailwind dev server is ALREADY RUNNING. Write `.svelte` files into the prototypes directory given in the user prompt; they hot-reload automatically. Do NOT start your own server, install packages, or modify the project's repo/config.
- Allowed writes — ONLY: prototype `.svelte` files in the sandbox prototypes dir, and $PLAN_FILE (to record decisions). Never touch real project source.
- Iterate with the user via the live preview: build a variant, ask, refine. Throwaway code — favour speed of exploration over polish.
- When direction is agreed, write/update a `## UI Decisions` section in $PLAN_FILE: layout, component structure, states/variants, interaction notes. You MAY tighten Scope bullets to match. Keep it concrete enough that implement is just a typist.
- Sentinel: on user-confirmed completion write exactly `ALL_GOOD` to $STEP_LOG; otherwise write a one-line reason.
