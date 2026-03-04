## Config Location

This file is symlinked from `~/.config/fish/claude/`. Always edit it there, not directly in `~/.claude/`.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
- Use the AskUserQuestion tool to resolve unresolved questions before finalizing the plan.

## Command Output

- Only save command output to a file when running tests, linters, or commands with known/potential failures. For simple commands (build, install, git, etc.) just run them directly.
- When saving output: `> ./tmp/output.txt 2>&1`, then process/query the file — never pipe long output inline or re-run commands to parse their output.
- Prefer `*:ai` versions of package.json scripts when available (e.g. `npm run lint:ai` not `npm run lint`).
- Run tests via project runners (e.g. NX), not directly via tool CLIs — runners set up necessary env vars.

## Commits

- Follow the repo's existing commit convention (check recent `git log` output).
- If no convention exists, use gitmoji style (e.g. `🐛 Fix race condition in session cleanup`).
