# Plan File Format

## Frontmatter

```yaml
---
description: "2-3 sentence summary of what this plan does and why."  # required — shown in progress output
branch: feat/...           # optional — git branch intent: present = ensure/create this branch; omit = adopt current checkout (interactive per-cwd chooser); `<current>` = adopt silently (no chooser)
test_cmds: |               # required — command(s) to run tests (scalar or multi-line list)
  npm run test:unit:ai
  npm run test:integration:ai
manual_test: ./plan-name.manual.md  # optional — path to manual test instructions file
pr_title: "..."             # optional — PR boundary marker: present = raise PR then autoplan stops for review/merge; omit = no PR, fold into next plan (commits only)
prompts: ./<slug>-N-prompts.md # required — path to THIS plan's dedicated prompts file (one prompts file per plan, never shared)
env_files:                  # optional — YAML list of dotenv files loaded (via dotenvx) for test_cmds
  - .semaphore/deployEnvironments/.staging-qa.env
next: ./<slug>-2.md         # optional — next plan in chain
cwd: ./monolith-free-sizing  # optional — subdir relative to autoplan launch dir; harness cds into it for this plan's duration (git, tests, commit all run there). Default: `.` (run root).
prototype: true             # optional boolean — if true, a prototype phase runs before implement (interactive Svelte sandbox for UI direction); omit or false to skip
commit_msg: "✨ Add ..."     # required — single-line gitmoji commit message for this plan's change; used by harness for deterministic commit (no LLM)
---
```

### env_files: Env Files for Harness-Run Commands

`env_files` is an optional YAML list of dotenv file paths, resolved relative to the directory autoplan runs from (the repo root), NOT the plan file. When set, the harness wraps every `test_cmds` entry as `dotenvx run -f <f1> -f <f2> -- <cmd>`. Requires `dotenvx` (`brew install dotenvx/brew/dotenvx`). Variables already set in the environment win over file values. Note that `test_cmds` run without `CI=true` during test/fix phases; use interactive or line-oriented reporters for readable failure output. Reference existing env files where possible rather than creating new ones.

### cwd: Per-Plan Working Directory

`cwd:` is an optional path (relative to the directory where `autoplan` is invoked, or absolute) that the harness `cd`s into for the duration of this plan. All git operations, test commands, and the commit run in that directory. When `cwd:` is set, `test_cmds` entries should NOT include a `cd <subdir> &&` prefix — the harness handles the directory change. Branch is also read and checked out in that directory. Note: `env_files` paths are still resolved relative to the autoplan launch dir (run root), not `cwd:`.

### prototype: UI Prototyping Gate

`prototype: true` gates an interactive prototype phase that runs before `implement`. When set, the harness launches a hot-reloading Vite+Svelte+Tailwind sandbox at a local URL and opens an interactive Claude session to build throwaway `.svelte` prototypes. The agent records agreed UI decisions into a `## UI Decisions` section in the plan body before advancing to `implement`. Omit or set to `false` to skip this phase entirely (the default).

### branch: Branch Intent

`branch:` encodes intent, not just a name:

- **`branch: <name>`** — ensure this branch: checkout if present locally; if absent and not resuming, create from `origin/main` (dirty-tree guard + `git fetch origin main` first).
- **`branch: <current>`** — adopt-current mode, **silent**: use whatever branch the repo is on, no chooser prompt.
- **`branch:` omitted** — adopt-current mode, **interactive**: a searchable fzf chooser appears pre-filled with the current branch; press Enter to keep it, or type a new name to create it off HEAD. Degrades silently if non-interactive or `fzf` is missing.

### test_cmds: Automated and Manual Verification

`test_cmds` runs automated tests. The harness runs each command as an independent checkpoint during the **test_fix phase** (sequential per-command: only failing commands get a fix loop; passing commands are not re-run). After all `test_cmds` pass, the `verify_cmds` phase re-runs all commands with `CI=true` and bundles a full aggregate report before any fix agent is invoked.

`test_cmds` is a YAML scalar or multi-line list. The harness runs each line as a separate command in sequence; all output is aggregated into `$TEST_LOG`. The fix_test agent reads `$TEST_LOG` to diagnose failures. Commands run **without** `CI=true` during test/fix; use interactive reporters or line-oriented output for readable failure messages.

```yaml
# Single command
test_cmds: npm run test:ai

# Multi-line list (each line runs as a separate independent checkpoint)
test_cmds: |
  npm run test:unit:ai
  npm run test:integration:ai
```

For flows that can't be auto-tested, set `manual_test` to a path pointing to a companion instructions `.md` file — the harness runs it after `test_cmds` pass and deletes the file before committing.

- **Automated only**: `test_cmds: npm run test:ai`
- **Manual only**: `manual_test: ./auth-refresh.manual.md` (omit `test_cmds` or leave as a no-op)
- **Both**: `test_cmds: npm run test:ai` + `manual_test: ./auth-refresh.manual.md`

All fields except `branch:`, `next:`, `pr_title:`, `manual_test:`, `env_files:`, and `cwd:` are required. `commit_msg` is technically optional (harness falls back to a Haiku LLM commit), but should always be set — omitting it is a quality gap flagged by refine. Paths in `prompts`, `manual_test`, and `next` are resolved relative to the plan file's directory; paths in `env_files` are resolved relative to the directory autoplan runs from.

## Body Sections

### Context
Why this work is needed. One or two sentences explaining the motivation or background.

### Scope
Concrete list of what to implement. Must name **specific files, functions, or interfaces** — not vague descriptions like "refactor X" or "improve Y".

Good:
- Add `UserAuthService.refreshToken(userId: string)` in `src/auth/user-auth.service.ts`
- Update `AuthController` to call `refreshToken` on 401 responses

Bad:
- Improve auth handling
- Refactor the service layer

### Verification
Specific, automatable checks — commands that pass or fail. Not subjective ("looks correct").

Good:
- `npm run test:ai -- --testPathPattern=auth`
- `npm run lint:ai`

Bad:
- Code looks correct
- Auth works as expected

### Out of Scope
Explicit list of known gaps NOT handled by this plan, each with reason or deferral pointer.
- <gap> — ignored because <reason>
- <gap> — deferred to ./<slug>-N.md

### UI Decisions

Auto-maintained by the prototype phase when `prototype: true` is set. Records the agreed UI direction: layout structure, component breakdown, states/variants, interaction notes. Written by the prototype agent after user confirmation; read by the implement phase. Do not write this section manually — let the prototype phase populate it.

## Example

First plan file (`auth-refresh-1.md`):

```markdown
---
description: "Add silent token refresh to the auth service. Access tokens currently expire after 1 hour and log users out; this plan adds a refresh endpoint and updates the controller to retry 401s transparently."
branch: feat/auth-refresh
test_cmds: npm run test:ai
pr_title: "Add token refresh to auth service"
prompts: ./auth-refresh-1-prompts.md
next: ./auth-refresh-2.md
commit_msg: "✨ Add silent token refresh endpoint and 401-retry controller"
---

# Add Token Refresh

## Context
Access tokens expire after 1 hour. Currently users are logged out; we need silent refresh.

## Scope
- Add `refreshToken(userId: string): Promise<string>` to `src/auth/user-auth.service.ts`
- Add `POST /auth/refresh` endpoint in `src/auth/auth.controller.ts`
- Add unit tests in `src/auth/user-auth.service.spec.ts`

## Verification
- `npm run test:ai -- --testPathPattern=user-auth.service`
- `npm run lint:ai`
```
