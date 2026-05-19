# Prompts File Format

**One prompts file per plan.** Each plan in a chain has its OWN dedicated prompts file (e.g. `<slug>-1-prompts.md`, `<slug>-2-prompts.md`). Never share a prompts file between plans, even if the rules would be identical — sharing produces generic prompts and "lazy" execution that drifts outside the plan's Scope. Each prompts file should be tailored to its specific plan's Scope.

## Global Rules (harness-owned — DO NOT restate or override)

Process rules — TDD ordering, plan-scope discipline, audit-only stance, sentinel-file write contracts, refactor-confirmation, the "no commit / no push / no PR" stage restriction, the "no lint/typecheck/build/full-test in worker" rule, and the test-integrity rules (no `.only`/`.skip`/TODO, every new public function gets a test, no manual_test file edits) — are injected by the harness as a phase-specific system prompt. They are **not adjustable** by plan or prompts files.

**Per-plan prompts files supply DOMAIN context only.** Forbidden in any section:

- TDD step lists (red/green/commit ordering).
- "Do NOT commit / push / stage / stash / reset / revert / ...".
- Plan-scope discipline statements ("only implement Scope", "ignore `next:`", etc.).
- Sentinel-file write contracts (`ALL_GOOD` / `ISSUES_FOUND`).
- "Audit-only" stance for verify.
- Refactor-confirmation language.
- Test integrity rules.
- "Do NOT run lint/typecheck/build/full test suites".

If you find any of the above in a prompts file, remove it — the harness already enforces it, and restating it risks drifting from the canonical wording.

## Available Variables

| Variable | Resolves to |
|----------|-------------|
| `$PLAN_FILE` | Absolute path to the current plan file |
| `$TEST_LOG` | `./tmp/autoplan-test-output.txt` |
| `$VERIFY_LOG` | `./tmp/autoplan-verify-result.txt` |
| `$VERIFY_CMD_LOG` | `./tmp/autoplan-verify-cmd-output.txt` |
| `$BRANCH` | The git branch name from plan frontmatter |
| `$TEST_CMD` | The test command from plan frontmatter |
| `$GATE_LOG` | `./tmp/autoplan-gate-output.txt` |

Inside a prompts file these variables are substituted into the per-plan section before it is interpolated into the user prompt. They are most useful for cross-referencing a log path in a domain note (e.g. "the playwright trace dir lives next to $TEST_LOG").

## Sections

A prompts file may contain any subset of these sections. Each is **domain context only** — short notes the worker should know about this project area:

- Paths and naming conventions specific to the project area (e.g. "tests live under `tests/playwright/`", "use the `User` factory in `tests/factories/user.ts`").
- Single-test-file run command (e.g. `npx nx run myapp:playwright:staging -- --reporter=line <file>`).
- Domain-specific call-outs (e.g. "always use `data-testid` selectors", "import auth helpers from `tests/helpers/auth.ts`", "the migration runner is `bin/migrate`").

If a section is missing or empty, the harness substitutes a "(none)" placeholder — the phase still runs against the harness-owned process rules.

### `## implement`

Domain context for the implement phase. The harness already invokes TDD via the system prompt; only add notes the worker needs about THIS plan's code area (helpers, naming, imports, file locations).

### `## fix_test`

Domain context for fixing failing tests. **Include the single-failing-file run command for this project area** — that is the most useful per-domain note.

Examples:
- Playwright/NX: `npx nx run myapp:playwright:staging -- --reporter=line <file>`
- Jest/NX: `npx nx run myapp:test -- --testPathPattern=<file>`
- npm Jest: `npm run test:ai -- --testPathPattern=<file>`

### `## fix_verify`

Domain context for fixing verify findings. Include the single-failing-file run command if it differs from `## fix_test`.

### `## fix_verify_cmd`

Domain context for fixing a failing `verify_cmds` entry (lint/typecheck/build/i18n/dead-code/etc.). Notes about per-check fix patterns specific to this project belong here (e.g. "translation keys live in `apps/web/locales/`", "lint config: `.eslintrc.cjs`").

### `## verify`

Domain context for the audit. The harness already supplies the audit-only stance and the structural checks; only add domain-specific things to look for (e.g. "no hardcoded selectors; all use `data-testid`", "no `console.log` left in production code").

### `## harden`

Domain context for the harden pass. Notes about per-area quality concerns (e.g. "this area uses optional chaining heavily — flag any `!.` non-null assertions"). Do **not** include shell commands or test-runner invocations — those belong in the plan's `verify_cmds:` frontmatter list.

For plans with flows that aren't auto-testable—UI walkthroughs, approval workflows, manual verification steps—create a companion `.md` file with instructions and set `manual_test: <path>` in the plan's frontmatter. The fix loops (`fix_test` and `fix_verify`) handle `MANUAL TEST FAILURE` markers the same way they handle automated test failures.

## Example (playwright-migrate context)

```markdown
# Prompts: migrate-auth-tests

## implement
- Use `data-testid` attributes for all selectors, never CSS classes or tag names.
- Import auth helpers from `tests/helpers/auth.ts`.
- New test files live in `apps/settings-frontend/tests/playwright/auth/`.

## fix_test
Single failing file: `npx nx run settings-frontend:playwright:staging-qa -- --reporter=line <failing-file>`
Traces land in `apps/settings-frontend/playwright-report/`.

## fix_verify
Single failing file: `npx nx run settings-frontend:playwright:staging-qa -- --reporter=line <affected-file>`

## fix_verify_cmd
Translations live under `apps/settings-frontend/locales/`. The lint config is `.eslintrc.cjs` at repo root.

## verify
- Confirm every selector uses `data-testid`; no CSS class or tag selectors.
- Confirm no `page.waitForTimeout` calls (use `expect(...).toBeVisible()` polling instead).

## harden
- This area uses Playwright fixtures heavily — prefer extending the existing `authedTest` fixture over inline `beforeEach` setup.
```
