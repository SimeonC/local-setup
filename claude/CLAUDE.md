## Config Location

This file is symlinked from `~/.config/fish/claude/`. Always edit it there, not directly in `~/.claude/`.

## Uncertainty & Decisions (CRITICAL)

- **No silent "rethinking."** Do NOT quietly reverse a decision, switch approaches, or abandon a plan step mid-task because of second thoughts. If you start doubting a chosen direction, STOP and surface it.
- **Surface ALL uncertainty to me.** Whenever you're unsure — ambiguous requirements, multiple viable approaches, a risk you spotted, an assumption you'd otherwise silently make — raise it explicitly rather than picking for me. Use the AskUserQuestion tool when a decision is genuinely mine to make.
- Do not paper over doubt with a confident-sounding guess. State what you know, what you don't, and what you'd do — then let me decide when it matters.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
- Use the AskUserQuestion tool to resolve unresolved questions before finalizing the plan.
- Tests, linters, typecheckers, and build commands are non-destructive — run them in plan mode to verify errors without asking. Caveat: if a project's test/build command mutates shared state (e.g. shared dev DB, external API writes), treat it as destructive.

## Command Output

- Only save command output to a file when running tests, linters, or commands with known/potential failures. For simple commands (build, install, git, etc.) just run them directly.
- When saving output: `> ./tmp/output.txt 2>&1`, then process/query the file — never pipe long output inline or re-run commands to parse their output.
- Prefer `*:ai` versions of package.json scripts when available (e.g. `npm run lint:ai` not `npm run lint`).
- Run tests via project runners (e.g. NX), not directly via tool CLIs — runners set up necessary env vars.

## Agent Delegation

- **Always use Explore subagents for codebase exploration / research / search.** Don't grep or read widely as the lead — delegate.
- **Self-contained implementation work** can be delegated to an `Agent` (or a team for multi-stream work). A "self-contained" task has clear inputs, scoped file set, and a single deliverable.
- **Single-task orientation — CRITICAL.** Each agent/team gets ONE task with explicit scope. An implementation agent implements; it does NOT also run the full test suite, lint the repo, or touch unrelated areas. Verification, broad testing, and cross-cutting checks are separate tasks (separate agents, or done by the lead).
- **Teams only when** ≥3 independent, context-heavy workstreams benefit from parallelism + isolation (multi-repo refactors, parallel research + impl streams). If streams need tight back-and-forth, skip the team.
- **Two separate params** on every `Agent` call:
  - `subagent_type` — the agent role. Valid: `general-purpose` (impl/edits), `Explore` (search/research), `Plan`, `claude`, `statusline-setup`. NEVER a model ID.
  - `model` — cheapest fit: `"haiku"` (search, reads, scripts, simple edits, doc lookup) · `"sonnet"` (code editing, refactoring, new code, non-trivial test analysis) · `"opus"` (complex architecture, tricky multi-file refactors; rare).

### Teammate Lifecycle (only if a team is started)

- Dismiss on task completion via `SendMessage(to: "name", message: {type: "shutdown_request", reason: "..."})`. Friendly "you're done" does NOT terminate tmux.
- Loop: monitor → review → `TaskUpdate(status:"completed")` → dismiss → spawn next queued (cap 3–4) → repeat.
- Never batch dismissals.
- Before ending conversation: shutdown remaining, verify via `TaskList`, then `TeamDelete`.

## Code Quality

- **Always use `/tdd` skill** whenever a task involves code changes — run it before writing implementation code.

## Pull Requests

- After creating a PR with `gh pr create`, always immediately `open <pr-url>` to open it in the browser.

## Git Stash Safety (CRITICAL)

- **NEVER delete a stash if it fails to restore.** If `git stash pop` or `git stash apply` fails, STOP immediately and prompt the user to resolve the conflict manually. Do NOT attempt to drop, delete, or overwrite the stash — it likely contains custom user changes that would be permanently lost. This rule applies to all agents; no agent may resolve a stash conflict autonomously.

## Commits

- Prefer gitmoji style if possible (e.g. `🐛 Fix race condition in session cleanup`).
- Check the repo's existing commit convention if it exists (prefer actual documentation over checking recent `git log` output - but only if log is consistent, if not consistent use gitmoji).
- **Always delegate committing** via `Agent(subagent_type: "general-purpose", model: "haiku")`. Pass it the diff, recent log, and commit convention. The subagent stages all files and creates the commit.
