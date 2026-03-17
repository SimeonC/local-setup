---
name: devcontainer-local-setup
description: Use when working on devcontainer port forwarding, .env.local files, or local environment variable overrides for devcontainers
---

# Devcontainer Local Setup

## Environment variables

Create `.devcontainer/.env.local` for machine-specific environment variables. `dco` reads this file and passes each `KEY=VALUE` line via `--remote-env` to the container. Comments (`#`) and blank lines are skipped.

```
# Local overrides
DATABASE_URL=postgres://localhost:5432/mydb
API_KEY=dev-secret
```

## Port config

Create `.devcontainer/ports.local` (gitignored, preferred) for machine-specific port config — one port per line, `#` comments supported:

```
# App server
3000
# HMR
3001
```

Alternatively, `.devcontainer/ports` (committed) can be used for shared/team-wide port config.

`forward-ports.sh` also auto-detects ports from:
- `vite.config.*` — `server.port`
- `.env*` files (`.env`, `.env.local`, `.env.development`) — `PORT=`, `VITE_PORT=`, `DEV_PORT=`, `APP_PORT=`
- `package.json` scripts — `--port`/`-p` flags

## Local devcontainer config

Use `dco --local` to prefer the workspace's `.devcontainer/devcontainer.json` over the global config. Without `--local`, `dco` always uses the global config at `~/.config/fish/claude/devcontainer/devcontainer.json`.

## Worktree port ranges

If using `/worktree-setup`, port blocks start at 4000 in increments of 100 (10 ports per repo per block). Check the root `CLAUDE.md` for existing assignments before picking a range.

## Gitignore

`.devcontainer/ports.local` and `.devcontainer/.env.local` are already in the global gitignore (`~/.gitignore_global`). Do **not** add them to local `.gitignore` files — this avoids unnecessary repo changes.
