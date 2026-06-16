Prototype the UI direction for the Scope of $PLAN_FILE. A Vite + Svelte + Tailwind dev server is already running at $PROTOTYPE_URL, serving `.svelte` files from $PROTOTYPE_DIR.

Process rules (single-plan discipline, allowed-writes restrictions, no-server/no-install, no-commit) are supplied by the harness system prompt. Read the plan's Scope, then collaborate with the user on UI direction through the live preview: write prototype `.svelte` files into $PROTOTYPE_DIR (they hot-reload at $PROTOTYPE_URL), show the user, and refine based on their feedback. These prototypes are throwaway — do not implement the real feature.

When direction is agreed, record the decisions into a `## UI Decisions` section in $PLAN_FILE (layout, component structure, states/variants, interaction notes) so the implement phase is just a typist.

Domain context for this plan:

$DOMAIN_PROTOTYPE

When you have fully completed this task, write exactly `ALL_GOOD` (and nothing else) to `$STEP_LOG`. If you stop early, are interrupted, or cannot complete it, do NOT write `ALL_GOOD` — write a one-line reason to `$STEP_LOG` instead.
