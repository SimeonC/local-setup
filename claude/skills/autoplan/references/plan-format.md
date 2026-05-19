# Plan File Format

## Frontmatter

```yaml
---
description: "2-3 sentence summary of what this plan does and why."  # required — shown in progress output
branch: feat/...           # required — git branch name
test_cmd: npm run test:ai   # required — command(s) to run tests
manual_test: ./plan-name.manual.md  # optional — path to manual test instructions file
pr_title: "..."             # optional — PR title string; omit to skip PR creation (commits only)
prompts: ./<slug>-N-prompts.md # required — path to THIS plan's dedicated prompts file (one prompts file per plan, never shared)
verify_cmds:                # optional — YAML list of deterministic shell commands run by the harness between harden_verify and commit
  - npm run lint:fix
  - npm run check
  - npm run test:unit
next: ./<slug>-2.md         # optional — next plan in chain
---
```

### verify_cmds: Deterministic Verification Commands

`verify_cmds` is an optional YAML list of shell commands executed by the fish harness (not Claude) between the `harden_verify` and `commit` phases. Use it for deterministic checks — lint, typecheck, build, test suites, i18n checks — where Claude exercises zero judgment on success. The harness runs each command in order, fail-fast: on the first non-zero exit, Claude is invoked with the `fix_verify_cmd` prompt to fix the failing command, then the loop restarts from the first command (to catch regressions from the fix). `test_cmd` still runs separately during the test/fix phase before harden.

### test_cmd: Automated and Manual Verification

`test_cmd` runs automated tests. For flows that can't be auto-tested, set `manual_test` to a path pointing to a companion instructions `.md` file — the harness runs it after `test_cmd` passes and deletes the file before committing.

- **Automated only**: `test_cmd: npm run test:ai`
- **Manual only**: `manual_test: ./auth-refresh.manual.md` (omit `test_cmd` or leave as a no-op)
- **Both**: `test_cmd: npm run test:ai` + `manual_test: ./auth-refresh.manual.md`

All fields except `next`, `pr_title`, and `manual_test` are required. Paths in `prompts`, `manual_test`, and `next` are resolved relative to the plan file's directory.

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
