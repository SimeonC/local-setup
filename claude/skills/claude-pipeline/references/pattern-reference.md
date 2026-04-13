# Claude Pipeline Pattern Reference

## The Pattern (Reference)

### 1. Stage Chain via `exec`

Scripts call each other with `exec` (not bash/sh), keeping the process stack flat and forwarding exported env vars:

```bash
# At the end of prepare.sh:
exec "$SCRIPT_DIR/migrate.sh"

# At the end of migrate.sh (after exporting state):
export BATCH_LABEL PR_ID
exec "$SCRIPT_DIR/test.sh"
```

Each script filename (`prepare.sh`, `migrate.sh`, `test.sh`, `verify.sh`) is also a **resume point** — the user can invoke any stage directly after an interruption.

### 1a. Thin `start.sh` Entry Point

Keep `start.sh` as a one-liner that simply execs the first real stage. This gives users a stable, obvious entry point while letting you rename/reorder internal stages freely:

```bash
#!/usr/bin/env bash
# start.sh — Entry point. Chains to: prepare.sh → migrate.sh → test.sh → verify.sh
exec "$(dirname "${BASH_SOURCE[0]}")/prepare.sh"
```

### 1b. Split "prepare" From First Work Stage

Separate cheap/idempotent pre-flight (fetch main, check for open PR, parse plan, create branch) into `prepare.sh`, and put the first expensive Claude invocation in a later stage (e.g. `migrate.sh`). Rationale:

- Resume is cleaner: rerunning `prepare.sh` is safe even when a branch+PR already exists for the batch.
- The work stage (`migrate.sh`) can be invoked directly on an existing branch with `BATCH_LABEL`/`PR_ID` derived from the branch name, without re-running PR-existence checks.
- Keeps each stage's responsibility narrow and independently debuggable.

### 2. State: Env Vars + Branch-Derived Fallback

State flows forward as exported env vars in the `exec` chain. Every stage after the first has a fallback that derives state from the current git branch + a markdown plan file, enabling manual resume:

```bash
if [ -z "${BATCH_LABEL:-}" ]; then
  BRANCH=$(git branch --show-current)
  slug="${BRANCH#<prefix>/}"
  while IFS= read -r line; do
    label=$(sed -n 's/.*`\([^`]*\)`.*/\1/p' <<< "$line")
    test_slug="${label//\//-}"; test_slug="${test_slug%%-}"
    if [ "$test_slug" = "$slug" ]; then
      BATCH_LABEL="$label"
      PR_ID=$(grep -oE 'PR [0-9]+' <<< "$line")
      break
    fi
  done < <(grep -E '^(## |- )' docs/<plan>.md | grep 'PR [0-9]')
  [ -z "${BATCH_LABEL:-}" ] && { log "ERROR: No plan entry matches branch $BRANCH"; exit 1; }
fi
```

### 3. Pre-flight Guards (Prepare Stage Only)

The prepare stage fetches main and checks for an already-open PR before doing work:

```bash
git fetch origin main

OPEN=$(gh pr list --state open --search '"[<tag>]" in:title' --json number --jq 'length')
if [ "$OPEN" -gt 0 ]; then
  log "PR already open — skipping."
  exit 0
fi
```

### 4. Headless Claude Invocation

Canonical form — always use this exact flag set:

```bash
claude --dangerously-skip-permissions --output-format stream-json --verbose \
  -p "$(cat <<'PROMPT'
<your prompt here>
PROMPT
)" | npx --yes @khanacademy/format-claude-stream
```

Quote the heredoc delimiter (`'PROMPT'`) to prevent shell expansion inside the prompt. If the prompt itself needs shell variables, use an unquoted delimiter and escape any literal `$` signs.

### 5. Retry Loop (Work Stage)

A bounded loop runs the validation command; on failure, calls Claude to fix:

```bash
LOG="$PWD/tmp/<task>-output.txt"
MAX_FIX_ATTEMPTS=3
FIX_ATTEMPT=0

while true; do
  if <validation-command> 2>&1 | tee "$LOG"; then
    break
  fi

  FIX_ATTEMPT=$((FIX_ATTEMPT + 1))
  if [ "$FIX_ATTEMPT" -ge "$MAX_FIX_ATTEMPTS" ]; then
    log "ERROR: Still failing after $MAX_FIX_ATTEMPTS attempts. See $LOG"
    exit 1
  fi

  claude --dangerously-skip-permissions --output-format stream-json --verbose \
    -p "$(cat <<'FIXPROMPT'
Tests are failing. Output is at $LOG. Read it, diagnose, and fix.
Commit any fixes.
FIXPROMPT
  )" | npx --yes @khanacademy/format-claude-stream
done
```

### 6. Sentinel-File Control Flow (Verify Stage)

Claude writes a sentinel word to a file; bash branches on it:

```bash
VERIFY_LOG="$PWD/tmp/<task>-verify-result.txt"

rm -f "$VERIFY_LOG"
claude --dangerously-skip-permissions --output-format stream-json --verbose \
  -p "$(cat <<VERPROMPT
Verify the work. If issues found: fix, commit, write CHANGES_MADE to $VERIFY_LOG.
If all good: write ALL_GOOD to $VERIFY_LOG, then push and create a PR.
VERPROMPT
)" | npx --yes @khanacademy/format-claude-stream

if grep -q "ALL_GOOD" "$VERIFY_LOG" 2>/dev/null; then
  log "Done."
  rm -f "$VERIFY_LOG"
elif grep -q "CHANGES_MADE" "$VERIFY_LOG" 2>/dev/null; then
  export VERIFY_PASS BATCH_LABEL PR_ID
  exec "$SCRIPT_DIR/test.sh"   # loop back
else
  log "ERROR: No sentinel written to $VERIFY_LOG"
  exit 1
fi
```

### 7. Bounded Loop-Back Counter

Prevent infinite verify↔test loops by re-exporting a pass counter:

```bash
MAX_VERIFY_PASSES=3
VERIFY_PASS="${VERIFY_PASS:-0}"
VERIFY_PASS=$((VERIFY_PASS + 1))
if [ "$VERIFY_PASS" -gt "$MAX_VERIFY_PASSES" ]; then
  log "ERROR: Loop exceeded $MAX_VERIFY_PASSES passes."
  exit 1
fi
```

### 8. Plan File as Durable State

A markdown plan file (e.g. `docs/<task>-plan.md`) tracks what's been done using strike-through:

```markdown
## PR 1: `feature/something` — Widget migration
- **PR 1**: Migrate widget tests

## ~~PR 2: `feature/other` — Other migration~~ DONE
- ~~**PR 2**: Migrate other tests~~
```

Stage 1 finds the first non-struck-through entry. After success, Claude adds `~~` + ` DONE`.

### 9. PR Creation (Final Stage)

```bash
git push origin "$BRANCH"
gh pr create \
  --title "🎭 Task: $BATCH_LABEL ($PR_ID) [<pipeline-tag>]" \
  --body "Batch $BATCH_LABEL. Part of <pipeline description>."
```

The `[<pipeline-tag>]` in the title is what the pre-flight check in stage 1 searches for.

### 10. Stage Boilerplate

Every stage opens with:

```bash
#!/usr/bin/env bash
# <name>.sh — <one-line purpose>. Resume point.
# Chains to: <next>.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
```

### 11. Sourced Helper for Background Services (e.g. preview server)

When the pipeline needs a long-running background service (preview server, DB, mock API) available across every stage, put the lifecycle logic in a **sourced** (not exec'd) helper file. Pattern:

- File is sourced at the top of every stage that needs the service: `source "$SCRIPT_DIR/<helper>.sh"; _ensure_service`.
- The PID is tracked in an **exported env var** (e.g. `PREVIEW_PID`) so it survives the `exec` chain.
- The helper registers an `EXIT` trap in each stage for cleanup — the trap fires only in the final stage of the chain (since `exec` replaces the process).
- `_ensure_service` is idempotent: if the PID is alive, return; otherwise kill any stale process on the target port, start the service, wait for readiness.

```bash
# preview-server.sh — sourced, not executed.
_kill_preview() {
  [ -n "${PREVIEW_PID:-}" ] || return 0
  kill "$PREVIEW_PID" 2>/dev/null || true
}
trap _kill_preview EXIT

_ensure_preview() {
  if [ -n "${PREVIEW_PID:-}" ] && kill -0 "$PREVIEW_PID" 2>/dev/null; then
    return 0
  fi
  # Kill anything already on the port (stale/wrong process).
  local existing_pid
  existing_pid=$(lsof -iTCP:8089 -sTCP:LISTEN -t 2>/dev/null || true)
  [ -n "$existing_pid" ] && kill "$existing_pid" 2>/dev/null || true

  mkdir -p tmp
  nohup <service-cmd> > tmp/<name>-preview.log 2>&1 &
  export PREVIEW_PID=$!

  # Bounded readiness wait (fail-fast if the process dies).
  local attempts=0
  while ! lsof -iTCP:8089 -sTCP:LISTEN &>/dev/null; do
    kill -0 "$PREVIEW_PID" 2>/dev/null || { log "ERROR: service died"; exit 1; }
    attempts=$((attempts + 1))
    [ "$attempts" -lt 90 ] || { log "ERROR: service not ready after 90s"; exit 1; }
    sleep 1
  done
}
```

Gotchas:
- The helper must be **sourced** with `source`/`.`, not run with `bash`/`exec` — it needs to set env vars in the current shell.
- Use `# shellcheck source=<file>.sh` on the line before `source` to appease shellcheck.
- Call `_ensure_service` in every stage that uses it. Early stages start it; later stages re-validate the PID and restart if needed.

## Conventions & Gotchas

| Rule | Reason |
|------|--------|
| Always `set -euo pipefail` | Catch unset vars and pipeline failures early |
| Always `cd $(git rev-parse --show-toplevel)` | Scripts run from repo root regardless of invocation dir |
| Re-`export` every state var before `exec` | `exec` replaces the process — unexported vars vanish |
| Use `$PWD/tmp/` for log files | Stays in-repo, gitignored, easy to inspect |
| Strip trailing `-` from branch slugs | `label//\//-` on `feature/` → `feature-` → trim with `%%-` |
| `exec` not `bash`/`sh` to chain stages | Keeps process stack flat; avoids signal-handling issues |
| `rm -f "$SENTINEL"` before Claude writes it | Prevents stale sentinel from a previous run |
| `grep -q "WORD" "$FILE" 2>/dev/null` | Handles missing file gracefully |
| Quote heredoc delimiter (`'PROMPT'`) | Prevents shell expansion inside prompt; use unquoted + `\$` if you need vars |
| Keep `[PR-tag]` consistent | Pre-flight search must match PR title format exactly |
| `start.sh` is a one-line `exec` into `prepare.sh` | Stable entry point; internal stages can be renamed/reordered freely |
| Split `prepare.sh` (pre-flight) from `<work>.sh` (first Claude invocation) | Prepare is cheap/idempotent; work stage can be invoked directly on an existing branch for resume |
| Source background-service helpers (don't exec) | `source <helper>.sh` sets env vars (e.g. `PREVIEW_PID`) in the current shell so the PID survives the exec chain |
| Export the service PID | Lets every stage check `kill -0 "$PREVIEW_PID"` across the exec chain |
| Kill stale process on port before start | Avoids "address in use" when prior run didn't clean up |
