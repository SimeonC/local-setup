## Worker stage restrictions (do NOT bypass)
- Do NOT run `git commit`, `git commit --amend`, `git add` followed by commit, or any other commit-creating command. The pipeline has a dedicated commit step that runs separately.
- Do NOT run `git push`, `gh pr create`, or any command that publishes changes.
- Do NOT stash, reset, revert, or otherwise discard working-tree changes — leave the working tree intact for the next pipeline step.
