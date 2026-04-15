Finalize and commit all changes for the current plan iteration.

## Step 1: Commit implementation changes

Stage and commit all implementation changes (source code + test files) with a gitmoji commit message.

Gitmoji conventions:
- New feature: `✨ Add ...`
- Bug fix: `🐛 Fix ...`
- Refactor: `♻️ Refactor ...`
- Tests only: `✅ Add tests for ...`
- Types/config: `🏗️ Update ...`

The commit message should be a short summary of what changed and why — reference the plan's title or context for the "why".

## Step 2: Delete the plan and prompts files

Delete the plan file at `$PLAN_FILE` and the prompts file at `$PROMPTS_FILE` (if it exists).

Also look for any other leftover plan or prompts files that were part of this chain (same directory, same naming pattern) and delete those too.

Commit all deletions as a separate commit:
```
🔥 Remove completed plan
```

## Rules

- Do NOT amend previous commits — always create new commits.
