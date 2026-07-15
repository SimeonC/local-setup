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

- **Always invoke the `swarm` skill both when planning a task AND when implementing a plan; also invoke `tdd` when the work involves code changes.**
- See the `swarm` skill for all sub-agent/team/model-tier/context rules.

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
