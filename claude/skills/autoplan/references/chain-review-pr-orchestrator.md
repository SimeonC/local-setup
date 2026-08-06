# Autoplan Chain Review + PR Body

Do the final chain-review and PR-body-generation phases of autoplan yourself, inline. This is simple enough that it needs NO sub-agents and NO teams. Do all the work directly.

Branch: $BRANCH
Plan directory: $PLAN_DIR

## Step 1: Review commits

Run: `git log --oneline $DIFF_BASE..$BRANCH`

Cross-check each commit against the PR intent and branch diff (`git diff $DIFF_BASE..$BRANCH`) to verify nothing was missed or left incomplete. Print a brief summary of what was completed and flag anything that looks incomplete.

## Step 2: Generate the PR body

Follow this prompt to generate the PR body, then write it to `./tmp/autoplan-pr-body.txt`:

```
$PR_BODY_PROMPT
```

## Step 3: Final status

Verify `./tmp/autoplan-pr-body.txt` exists, then print:

- `Chain-review+PR complete.` if the file exists.
- `Chain-review+PR complete: pr-body.txt missing.` otherwise.

Then exit.

## Rules

- Do the work yourself inline. Do NOT spawn sub-agents or create teams.
- Do NOT run `git push` or `gh pr create` — fish will do that after reading the sentinel.
- Review must complete before PR-body so the PR reflects the final commits.
