---
name: pull-request
description: Conventions for creating and handling pull requests with the gh CLI. Use when opening, updating, or reviewing a PR — anything involving `gh pr`.
---

# Pull Requests

- Write the PR description to a markdown file and pass it with `gh pr create --body-file <path>` or `gh pr edit --body-file <path>`; do not pass multiline markdown through an inline shell argument with escaped `\\n`, because those escapes can appear literally in the rendered description.
- After creating a PR with `gh pr create`, always immediately `open <pr-url>`
  to open it in the browser.
