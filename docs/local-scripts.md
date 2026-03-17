# Local Scripts Convention

Projects can provide per-directory fish scripts that `dev`, `start`, and `dco` source automatically.

## Files

| File | Purpose | Sourced by |
|------|---------|------------|
| `local_env.fish` | Non-blocking env setup (docker containers, deps) | `dev`, `start`, `dco` |
| `local_dev.fish` | Development start command | `dev` only |
| `local_start.fish` | Production-like start command | `start` only |

## Execution Order

1. `local_env.fish` runs first (if present) — must be non-blocking
2. Then `local_dev.fish` or `local_start.fish` depending on which command was invoked
3. `dco` only runs `local_env.fish` (never the start scripts, since it launches a devcontainer)

## Why the Split

`dco` needs env setup (e.g. starting Docker containers) but must not run blocking commands like `rails s` or `npm run dev` — otherwise `devcontainer up` never executes. Separating env setup into `local_env.fish` solves this.
