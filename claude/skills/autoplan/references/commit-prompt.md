Finalize and commit all changes for the current plan iteration.

Use the `commit` skill for the message convention and the git safety rules.

## Step 1: Commit implementation changes

Run `git add -A` to stage ALL changes in the repo (do NOT cherry-pick files — stage everything), then commit with a gitmoji commit message.

The commit message should be a short summary of what changed and why — reference the plan's title or context for the "why".

## Rules

- Do NOT amend previous commits — always create new commits.

When you have fully completed this task, write exactly `ALL_GOOD` (and nothing else) to `$STEP_LOG`. If you stop early, are interrupted, or cannot complete it, do NOT write `ALL_GOOD` — write a one-line reason to `$STEP_LOG` instead.
