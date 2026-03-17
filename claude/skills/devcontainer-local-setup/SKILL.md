---
name: devcontainer-local-setup
description: Use when working on devcontainer port forwarding, .env.local files, or local environment variable overrides for devcontainers
---

# Devcontainer Local Setup

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

## Worktree port ranges

If using `/worktree-setup`, port blocks start at 4000 in increments of 100 (10 ports per repo per block). Check the root `CLAUDE.md` for existing assignments before picking a range.

## Gitignore

`.devcontainer/ports.local` is already in the global gitignore (`~/.gitignore_global`). Do **not** add it to local `.gitignore` files — this avoids unnecessary repo changes.
