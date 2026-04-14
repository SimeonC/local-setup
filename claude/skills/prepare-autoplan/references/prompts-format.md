# Prompts File Format

## Available Variables

| Variable | Resolves to |
|----------|-------------|
| `$PLAN_FILE` | Absolute path to the current plan file |
| `$TEST_LOG` | `./tmp/autoplan-test-output.txt` |
| `$VERIFY_LOG` | `./tmp/autoplan-verify-result.txt` |
| `$BRANCH` | The git branch name from plan frontmatter |
| `$TEST_CMD` | The test command from plan frontmatter |
| `$GATE_LOG` | `./tmp/autoplan-gate-output.txt` |

## Sections

A prompts file must contain all 5 sections, each introduced by `## <section-name>`.

### `## implement`

Domain-specific implementation instructions. Must reference the plan file and invoke the TDD skill.

Template:
```
Read the plan at $PLAN_FILE. Use /tdd skill — write tests first (RED), then implement to pass (GREEN).
Rules:
- [domain conventions: imports, file locations, patterns]
- Follow SOLID principles.
- Do NOT commit.
```

### `## fix_test`

Instructions for fixing failing tests. Must follow TDD red→green→commit. Include **how to run a single failing test file** — this is domain-specific and must be filled in.

Template:
```
Tests are failing. Output at $TEST_LOG.
Follow TDD: red → green → commit.
1. Read the test output to understand failures.
2. Run the failing tests to confirm: [HOW TO RUN SINGLE FAILING FILE]
3. Fix the root cause. Do NOT weaken assertions. Do NOT skip or remove tests.
4. Re-run tests to confirm they pass.
5. Commit fixes.
```

> **Note:** `[HOW TO RUN SINGLE FAILING FILE]` is domain-specific. Examples:
> - Playwright/NX: `npx nx run myapp:playwright:staging -- --reporter=line <file>`
> - Jest/NX: `npx nx run myapp:test -- --testPathPattern=<file>`
> - npm Jest: `npm run test:ai -- --testPathPattern=<file>`

### `## fix_verify`

Instructions for fixing issues flagged by the verify step. Must follow TDD red→green→commit.

Template:
```
Verify step found issues. Read $VERIFY_LOG.
Follow TDD: red → green → commit.
1. Read each issue.
2. Run the affected tests to confirm: [HOW TO RUN SINGLE FAILING FILE]
3. Fix the issues. Do NOT weaken, skip, or remove tests. Do NOT push or open a PR.
4. Re-run tests to confirm they pass.
5. Commit fixes.
```

### `## verify`

Audit-only checklist. The agent must NOT edit files, commit, push, or open PRs. Must write a sentinel to `$VERIFY_LOG`.

Template:
```
Read the plan at $PLAN_FILE. Audit all changes on branch $BRANCH. YOUR ROLE IS AUDIT-ONLY. Do NOT edit files, commit, push, or open a PR.
Check:
1. [specific structural check — e.g. "All scope items from the plan are implemented"]
2. [specific structural check — e.g. "No test files skip or weaken assertions"]
3. [domain check — e.g. "No hardcoded selectors; all use data-testid attributes"]
4. No regressions. SOLID principles. No dead code.
If ALL pass: write ALL_GOOD to $VERIFY_LOG.
If ANY fail: write ISSUES_FOUND on line 1 of $VERIFY_LOG, numbered issues below.
```

### `## harden`

Refactoring pass after tests pass. Focus on quality issues, not new features.

Template:
```
Review all uncommitted changes. Fix: duplication, SOLID violations, dead code, missing coverage.
Re-run tests after each change. Context: $PLAN_FILE.
Do NOT commit.
```

## Example (playwright-migrate context)

```markdown
# Prompts: migrate-auth-tests

## implement
Read the plan at $PLAN_FILE. Use /tdd skill — write tests first (RED), then implement to pass (GREEN).
Rules:
- Use `data-testid` attributes for all selectors, never CSS classes or tag names.
- Import helpers from `tests/helpers/auth.ts`.
- Follow SOLID principles.
- Do NOT commit.

## fix_test
Tests are failing. Output at $TEST_LOG.
Follow TDD: red → green → commit.
1. Read the test output to understand failures.
2. Run the failing tests to confirm: npx nx run settings-frontend:playwright:staging-qa -- --reporter=line <failing-file>
3. Fix the root cause. Do NOT weaken assertions. Do NOT skip or remove tests.
4. Re-run tests to confirm they pass.
5. Commit fixes.

## fix_verify
Verify step found issues. Read $VERIFY_LOG.
Follow TDD: red → green → commit.
1. Read each issue.
2. Run the affected tests to confirm: npx nx run settings-frontend:playwright:staging-qa -- --reporter=line <affected-file>
3. Fix the issues. Do NOT weaken, skip, or remove tests. Do NOT push or open a PR.
4. Re-run tests to confirm they pass.
5. Commit fixes.

## verify
Read the plan at $PLAN_FILE. Audit all changes on branch $BRANCH. YOUR ROLE IS AUDIT-ONLY. Do NOT edit files, commit, push, or open a PR.
Check:
1. All scope items from the plan are implemented.
2. No test uses CSS class or tag selectors — only data-testid.
3. No test skips, only-marks, or weakened assertions.
4. No regressions in existing tests. SOLID principles. No dead code.
If ALL pass: write ALL_GOOD to $VERIFY_LOG.
If ANY fail: write ISSUES_FOUND on line 1 of $VERIFY_LOG, numbered issues below.

## harden
Review all uncommitted changes. Fix: duplication, SOLID violations, dead code, missing coverage.
Re-run tests after each change. Context: $PLAN_FILE.
Do NOT commit.
```
