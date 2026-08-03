# Plan File Format

## Frontmatter

```yaml
---
description: "2-3 sentence summary of what this plan does and why."  # required — shown in progress output
branch: feat/...           # optional — git branch intent: present = ensure/create this branch; omit = adopt current checkout (interactive per-cwd chooser); `<current>` = adopt silently (no chooser)
test_cmd: npm run test:ai   # required — command(s) to run tests
manual_test: ./plan-name.manual.md  # optional — path to manual test instructions file
pr_title: "..."             # optional — PR boundary marker: present = raise PR then autoplan stops for review/merge; omit = no PR, fold into next plan (commits only)
stack_base: feat/prev-layer # optional — parent branch this layer stacks on: branch off it (not origin/main), PR targets it, and register a GitHub stack. See stack_base section.
prompts: ./<slug>-N-prompts.md # required — path to THIS plan's dedicated prompts file (one prompts file per plan, never shared)
verify_cmds:                # optional — YAML list of deterministic shell commands run by the harness between harden_verify and commit
  - npm run lint:fix
  - npm run check
  - npm run test:unit
env_files:                  # optional — YAML list of dotenv files loaded (via dotenvx) for test_cmd and verify_cmds
  - .semaphore/deployEnvironments/.staging-qa.env
next: ./<slug>-2.md         # optional — next plan in chain
cwd: ./monolith-free-sizing  # optional — subdir relative to autoplan launch dir; harness cds into it for this plan's duration (git, tests, commit all run there). Default: `.` (run root).
prototype: true             # optional boolean — if true, a prototype phase runs before implement (interactive Svelte sandbox for UI direction); omit or false to skip
commit_msg: "✨ Add ..."     # required — single-line gitmoji commit message for this plan's change; used by harness for deterministic commit (no LLM)
---
```

### env_files: Env Files for Harness-Run Commands

`env_files` is an optional YAML list of dotenv file paths, resolved relative to the directory autoplan runs from (the repo root), NOT the plan file. When set, the harness wraps every `test_cmd` segment and every `verify_cmds` entry as `dotenvx run -f <f1> -f <f2> -- <cmd>`. Requires `dotenvx` (`brew install dotenvx/brew/dotenvx`). Variables already set in the environment win over file values. Note that `verify_cmds` run with `CI=true` exported (non-interactive lint/build/test), whereas `test_cmd` runs without it. Reference existing env files where possible rather than creating new ones.

### cwd: Per-Plan Working Directory

`cwd:` is an optional path (relative to the directory where `autoplan` is invoked, or absolute) that the harness `cd`s into for the duration of this plan. All git operations, test commands, `verify_cmds`, and the commit run in that directory. When `cwd:` is set, `test_cmd` and `verify_cmds` should NOT include a `cd <subdir> &&` prefix — the harness handles the directory change. Branch is also read and checked out in that directory. Note: `env_files` paths are still resolved relative to the autoplan launch dir (run root), not `cwd:`.

### prototype: UI Prototyping Gate

`prototype: true` gates an interactive prototype phase that runs before `implement`. When set, the harness launches a hot-reloading Vite+Svelte+Tailwind sandbox at a local URL and opens an interactive Claude session to build throwaway `.svelte` prototypes. The agent records agreed UI decisions into a `## UI Decisions` section in the plan body before advancing to `implement`. Omit or set to `false` to skip this phase entirely (the default).

### branch: Branch Intent

`branch:` encodes intent, not just a name:

- **`branch: <name>`** — ensure this branch: checkout if present locally; if absent and not resuming, create from `origin/main` (dirty-tree guard + `git fetch origin main` first).
- **`branch: <current>`** — adopt-current mode, **silent**: use whatever branch the repo is on, no chooser prompt.
- **`branch:` omitted** — adopt-current mode, **interactive**: a searchable fzf chooser appears pre-filled with the current branch; press Enter to keep it, or type a new name to create it off HEAD. Degrades silently if non-interactive or `fzf` is missing.

### stack_base: Stacked PRs

`stack_base: <branch>` opts a PR layer into a GitHub stacked pull request (requires the `github/gh-stack` extension and a repo with stacked PRs enabled). It only makes sense on a plan that has both `branch:` and `pr_title:`. Effects:

- **Branch creation**: the branch is created off `stack_base` instead of `origin/main` (local ref preferred, else `origin/<stack_base>`).
- **PR create**: `gh pr create --base <stack_base>`, then `gh stack link <stack_base> <branch>` registers the parent→child stack on GitHub. Each PR shows only its own layer's diff.
- **No pause**: normally a `pr_title:` plan pauses after raising its PR so you merge before the next plan. When the **next** plan has a `stack_base:`, autoplan does NOT pause — it keeps running the whole stack in one invocation. GitHub auto-retargets/rebases children as parents merge. A `pr_title:` boundary whose successor has no `stack_base:` still pauses as before (so mixed chains work).

**Parent branch may not exist yet.** A `stack_base` usually names the `branch:` of an earlier plan in the same chain — that branch is created when the earlier plan runs, not before. The up-front preflight accepts a `stack_base` that either resolves to an existing ref *or* matches the `branch:` of an earlier plan in the chain; it only fails when it is neither.

### verify_cmds: Deterministic Verification Commands

`verify_cmds` is an optional YAML list of shell commands executed by the fish harness (not Claude) between the `harden_verify` and `commit` phases. Use it for deterministic checks — lint, typecheck, build, test suites, i18n checks — where Claude exercises zero judgment on success. The harness runs each command in order, fail-fast: on the first non-zero exit, Claude is invoked with the `fix_verify_cmd` prompt to fix the failing command, then the loop restarts from the first command (to catch regressions from the fix). `test_cmd` still runs separately during the test/fix phase before harden.

### test_cmd: Automated and Manual Verification

`test_cmd` runs automated tests. For flows that can't be auto-tested, set `manual_test` to a path pointing to a companion instructions `.md` file — the harness runs it after `test_cmd` passes and deletes the file before committing.

- **Automated only**: `test_cmd: npm run test:ai`
- **Manual only**: `manual_test: ./auth-refresh.manual.md` (omit `test_cmd` or leave as a no-op)
- **Both**: `test_cmd: npm run test:ai` + `manual_test: ./auth-refresh.manual.md`

All fields except `branch:`, `next:`, `pr_title:`, `stack_base:`, `manual_test:`, `env_files:`, and `cwd:` are required — including `commit_msg`, which the preflight now enforces (a missing `commit_msg` fails the run before any work). Paths in `prompts`, `manual_test`, and `next` are resolved relative to the plan file's directory; paths in `env_files` are resolved relative to the directory autoplan runs from.

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
test_cmd: npm run test:ai
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
