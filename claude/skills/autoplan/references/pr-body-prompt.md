Generate a pull request summary for branch `$BRANCH` against `$DIFF_BASE`.

## Data sources

- Run `git log $DIFF_BASE..$BRANCH --oneline` to see all commits.
- Run `git diff $DIFF_BASE...$BRANCH --stat` to see changed files.
- Run `git diff $DIFF_BASE...$BRANCH` for the full diff if needed for context.

## Output

Write the PR body as markdown to `./tmp/autoplan-pr-body.txt`. No preamble, no commentary — just the markdown content.

### Structure

```markdown
## Summary

- [1-3 bullet points: what was done and why]

## Changes

- **path/to/file.ext**: [what changed in this file]
- **path/to/other.ext**: [what changed]

---
*Generated with autoplan*
```

## Rules

- Keep the summary concise — focus on what and why, not how.
- Group related file changes together rather than listing every file individually.
- Do NOT include temporary files, plan files, or prompts files in the changes list.
- Do NOT add any text before or after the markdown body.
