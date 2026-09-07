The commit step FAILED — see `$COMMIT_LOG` for the error. The cause is usually a pre-commit hook rejection (lint, format, or type gate). Fix the underlying issues, re-stage with `git add -A`, and create the commit.

`$COMMIT_MSG` is the suggested commit message. If it is non-empty, use it exactly. If it is empty, author a new gitmoji commit message (see conventions below).

## Step 1: Review the failure

Read `$COMMIT_LOG` to understand what failed. Common causes:
- **Lint errors** — run the linter and fix violations
- **Type errors** — fix TypeScript/type issues reported
- **Format errors** — run the formatter (e.g. prettier, gofmt)
- **Test gate** — a pre-commit test runner failed; fix the failing tests

## Step 2: Fix the underlying issues

Resolve whatever the hook or error reported. Make minimal targeted fixes — do not refactor or change unrelated code.

## Step 3: Commit

Run `git add -A` to stage ALL changes in the repo (do NOT cherry-pick files — stage everything), then commit.

If `$COMMIT_MSG` is non-empty, use it as the commit message.

If `$COMMIT_MSG` is empty, author a gitmoji message — see the `commit` skill for
the conventions and git safety rules.

The commit message should be a short summary of what changed and why — reference the plan at `$PLAN_FILE` for context.

## Rules

- Do NOT amend previous commits — always create new commits.
- Do NOT skip pre-commit hooks (no `--no-verify`).

When you have fully completed this task, write exactly `ALL_GOOD` (and nothing else) to `$STEP_LOG`. If you stop early, are interrupted, or cannot complete it, do NOT write `ALL_GOOD` — write a one-line reason to `$STEP_LOG` instead.
