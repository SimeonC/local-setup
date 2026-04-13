---
name: claude-pipeline
description: Scaffold or reason about multi-stage bash pipelines that drive headless Claude to perform batched, resumable work (migrations, codemods, mass refactors). Use when user wants a chained script that loops Claude over a plan file with retries and PR creation.
user_invocable: true
user_invocable_name: /scaffold-claude-pipeline
---

# Claude Pipeline Pattern

A **claude pipeline** is a chain of bash stage scripts that each invoke headless `claude -p` to perform one slice of a large, batched, automatable task. Each stage is independently resumable. The chain ends by pushing a branch and opening a PR.

## When to Use

This pattern fits when:
- Work can be broken into batches described in a markdown plan file
- Each batch needs: a Claude work step → automated test/validation → a verification pass → a PR
- Interruption is likely (long-running, CI, flaky tests) — so resume-from-branch matters
- You want an audit trail: each batch = one branch = one PR with a consistent title format

Canonical example: `settings-frontend/scripts/playwright-migrate/{start,prepare,migrate,test,verify}.sh` (+ sourced `preview-server.sh`) — migrates Cypress test batches to Playwright, one batch per PR.

---

## Pattern Reference

See [references/pattern-reference.md](references/pattern-reference.md) for the 11-section pattern definition (stage chain, state handling, pre-flight guards, headless Claude invocation, retry loop, sentinel control flow, bounded loop-back, plan file, PR creation, stage boilerplate, sourced service helpers) and the Conventions & Gotchas table.

---

## Scaffolding Flow

When `/scaffold-claude-pipeline` is invoked, gather requirements with `AskUserQuestion`, then generate the scripts.

### Step 1 — Gather Info

Ask the user (two `AskUserQuestion` calls if needed, max 4 questions each):

**Round 1:**
1. **Task name** — becomes `scripts/<name>/` and the branch prefix (e.g. `playwright-migrate` → branches named `playwright/<label>`)
2. **Stages** — list of stage script names in order (default: `start` (thin entry) → `prepare` (pre-flight/branch) → `<work>` (first Claude invocation, e.g. `migrate`) → `test` → `verify`)
3. **Plan file path** — relative to repo root (e.g. `docs/playwright-migration-plan.md`)
4. **PR title tag** — the `[tag]` suffix used in pre-flight check (e.g. `playwright-migration`)
5. **Background service?** — does the pipeline need a long-running service (preview server, DB, mock API) available across stages? If yes, a sourced `<service>.sh` helper is generated.

**Round 2 (per stage):**
For each stage, ask:
- What command/tool does Claude run or invoke? (e.g. `npx nx run settings-frontend:playwright`)
- What is Claude's goal in this stage? (work / fix / verify)
- Max retry/loop attempts (default: 3)
- Sentinel words if it's the verify stage (default: `ALL_GOOD` / `CHANGES_MADE`)

### Step 2 — Generate Scripts

For each stage, emit a `.sh` file following the boilerplate + relevant pattern elements. Use the information gathered to fill:
- The `claude -p` prompt body
- The validation command and `LOG` path
- The sentinel words and loop-back target
- The `exec` chain to the next stage

Also generate a `README.md` in `scripts/<name>/` documenting:
- What each stage does
- How to resume from each stage manually (what env vars to set, or just run the script on the right branch)
- The plan file format expected

### Step 3 — Post-generation Checks

After writing the files:
1. `chmod +x scripts/<name>/*.sh`
2. Confirm the sentinel words used in verify match those Claude is instructed to write
3. Confirm the `[PR-tag]` in the pre-flight gh search matches the `--title` in the final `gh pr create`
4. Confirm `tmp/` is in `.gitignore` (add `tmp/` if missing)

---

## Verification

See [references/verification-checklist.md](references/verification-checklist.md) for the post-scaffold checklist.
