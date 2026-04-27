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

## Agent Delegation

- **Default: work directly.** Do not auto-create a team. Use `Agent` (one-shot subagents) or direct tools as appropriate.
- **Use a team only when** the task has multiple independent, context-heavy workstreams that benefit from parallelism and isolation — e.g. multi-repo refactors, simultaneous research + implementation streams, 3+ tasks with little cross-dependency. If streams need to share context or hand results back and forth tightly, skip the team.
- **Ad-hoc subagents are fine** for delegated search/research/isolated edits without a team.
- **Model tier selection** (applies to both teammates and ad-hoc agents) — pick cheapest tier that fits:
  - `"haiku"`: code search, grep/glob, reading files, running scripts, simple edits, research/doc lookup.
  - `"default"`: code editing, refactoring, non-trivial test analysis, writing new code.
  - `"best"`: complex architectural decisions, tricky multi-file refactors. Rare.

### Teammate Lifecycle (only relevant if a team is started)

- Dismiss teammates immediately on task completion via `SendMessage(to: "name", message: {type: "shutdown_request", reason: "..."})`. A friendly "you're done" does not terminate the tmux session.
- Orchestration loop: monitor → review → `TaskUpdate(status:"completed")` → dismiss → spawn next queued (cap 3–4 concurrent) → repeat.
- Never batch dismissals.
- Before ending conversation: shutdown remaining teammates, verify via `TaskList`, then `TeamDelete`.

## Code Quality

- **Always adhere to SOLID principles** (Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion) when writing or modifying code.
- **Always use `/tdd` skill** whenever a task involves code changes — run it before writing implementation code.

## Pull Requests

- After creating a PR with `gh pr create`, always immediately `open <pr-url>` to open it in the browser.

## Git Stash Safety (CRITICAL)

- **NEVER delete a stash if it fails to restore.** If `git stash pop` or `git stash apply` fails, STOP immediately and prompt the user to resolve the conflict manually. Do NOT attempt to drop, delete, or overwrite the stash — it likely contains custom user changes that would be permanently lost. This rule applies to all agents; no agent may resolve a stash conflict autonomously.

## Commits

- Follow the repo's existing commit convention (check recent `git log` output).
- If no convention exists, use gitmoji style (e.g. `🐛 Fix race condition in session cleanup`).
