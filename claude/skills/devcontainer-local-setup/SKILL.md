---
name: devcontainer-local-setup
description: Use when working on devcontainer port forwarding, .env.local files, or local environment variable overrides for devcontainers
---

# Devcontainer Local Setup

## Port config

Create `.devcontainer/ports` (committed) and `.devcontainer/ports.local` (gitignored) — one port per line, `#` comments supported:

```
# App server
3000
# HMR
3001
```

`forward-ports.sh` also auto-detects ports from:
- `vite.config.*` — `server.port`
- `.env*` files — `PORT=`, `VITE_PORT=`, `DEV_PORT=`, `APP_PORT=`
- `package.json` scripts — `--port`/`-p` flags

## Local env

`.env.local` at the project root is sourced by `forward-ports.sh` for port detection. To load vars into your fish shell use `loadenv`:

```fish
loadenv .env.local
```

`loadenv` supports single/double/triple quotes and multi-line values.

## Worktree port ranges

If using `/worktree-setup`, port blocks start at 4000 in increments of 100 (10 ports per repo per block). Check the root `CLAUDE.md` for existing assignments before picking a range.

## Gitignore reminder

Ensure both are gitignored:
```
.devcontainer/ports.local
.env.local
```
