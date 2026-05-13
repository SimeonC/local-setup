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

## Step 2: Delete completed plan file(s)

Delete the plan file at `$PLAN_FILE`.

$PROMPTS_CLEAN

Do NOT delete any other files.

Commit the deletion(s) as a separate commit:
```
🔥 Remove completed plan
```

## Rules

- Do NOT amend previous commits — always create new commits.
