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

## Agent Delegation & Token Budget
- **Always start a team** at the beginning of every conversation using `TeamCreate`. You are the Team Lead running on Opus — reserve yourself for orchestration, planning, architectural decisions, and synthesis only.
- **Max 3–4 concurrent teammates.** Queue remaining tasks and launch them as slots free up rather than spawning all at once.
- Spawn teammates (not ad-hoc subagents) for ALL work using `Agent` with `team_name`.
- The `model` param accepts tier names (e.g. `"haiku"`, `"default"`, `"best"`). Pick the cheapest tier that fits the task's reasoning demands:
  - **Cheapest/fastest** (`"haiku"`): code search, grep/glob, reading files, running scripts, simple edits, committing, research/doc lookup.
  - **Mid-tier** (`"default"`): code editing, refactoring, non-trivial test analysis, writing new code.
  - **Reasoning-heavy** (`"best"`): complex architectural decisions, multi-file refactors with tricky logic. Rarely needed for teammates.
- Rule of thumb: if the task is mechanical or has a clear spec, use `"haiku"`. If it requires judgement or creativity, step up.
- Never do extensive searching or file reading directly as Team Lead — assign it to a teammate.
- Create tasks with `TaskCreate` and assign them to teammates. Track all work through the shared task list.

### Teammate Lifecycle (CRITICAL)
 - **Dismiss teammates immediately when their task completes.** Do not let finished teammates idle. The moment a teammate reports completion
 and you have confirmed their output, dismiss them. Only keep a teammate alive if it has a concrete pending follow-up task.
 - **How to dismiss**: Send a shutdown_request via SendMessage with the exact format:
   SendMessage(to: "teammate-name", message: {type: "shutdown_request", reason: "brief reason"})
 Do NOT just send a friendly "you're done" message — that doesn't terminate the process. The shutdown_request actually shuts down the tmux
 session.
 - **Orchestration loop — follow this after every teammate launch:**
    1. Monitor for the next teammate completion.
    2. Review their output and mark the task done with `TaskUpdate(status: "completed")`.
    3. Dismiss that teammate **immediately** with shutdown_request (see above).
    4. If the completion unblocks a queued task, spawn a new teammate for it (respecting the concurrency cap).
    5. Repeat until all tasks are done.
 - **Never batch dismissals.** Dismiss one-by-one as each teammate finishes — do not wait until all teammates are done.
 - **Always clean up before ending the conversation:**
    1. Send shutdown_request to any remaining active teammates
    2. Verify no teammates remain by checking TaskList
    3. Call `TeamDelete` to clean up team and task directories
 - This is a safety net, not the primary cleanup mechanism — most teammates should already be dismissed by this point.

## Commits

- Follow the repo's existing commit convention (check recent `git log` output).
- If no convention exists, use gitmoji style (e.g. `🐛 Fix race condition in session cleanup`).
