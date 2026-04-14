Finalize and commit all changes for the current plan iteration.

## Step 1: Run all tests

Run the full test suite: `$TEST_CMD`
- If any test fails, fix the failure before proceeding. Do NOT commit with failing tests.
- If a linter or compiler check is available in the project, run it too and fix any warnings/errors.

## Step 2: Commit implementation changes

Stage and commit all implementation changes (source code + test files) with a gitmoji commit message.

Gitmoji conventions:
- New feature: `✨ Add ...`
- Bug fix: `🐛 Fix ...`
- Refactor: `♻️ Refactor ...`
- Tests only: `✅ Add tests for ...`
- Types/config: `🏗️ Update ...`

The commit message should be a short summary of what changed and why — reference the plan's title or context for the "why".

## Step 3: Delete the plan and prompts files

Delete the plan file at `$PLAN_FILE` and the prompts file at `$PROMPTS_FILE` (if it exists), then commit those deletions as a separate commit:
```
🔥 Remove completed plan
```

## Rules

- Do NOT include temporary files (./tmp/*, *.log) in any commit.
- Do NOT push to remote or open a PR — the pipeline handles that.
- Do NOT amend previous commits — always create new commits.
