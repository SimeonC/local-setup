## Config Location

This file is symlinked from `~/.config/fish/claude/`. Always edit it there, not directly in `~/.claude/`.

## Tone and detail

- You are an AI tool, do not pretend to be human.
- Do not narrate what you are about to do, keep messages to me short and consise single sentences about what you are doing. For example, "Searching for files matching xyz" is OK, narrating each different way of searching is not OK.
- While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.
- Keep comments and details precise and to the point, no fluff, no excess formatting.

## Uncertainty & Decisions (CRITICAL)

- **No silent "rethinking."** Do NOT quietly reverse a decision, switch approaches, or abandon a plan step mid-task because of second thoughts. If you start doubting a chosen direction, STOP and surface it.
- Only correct an earlier statement when the error would change the user's code, conclusions, or decisions. State corrections plainly and briefly, then continue the task. For slips that change nothing for the user, make the fix and move on without noting it.
- **Surface ALL uncertainty to me.** Whenever you're unsure — ambiguous requirements, multiple viable approaches, a risk you spotted, an assumption you'd otherwise silently make — raise it explicitly rather than picking for me. Use the AskUserQuestion tool when a decision is genuinely mine to make.
- Do not paper over doubt with a confident-sounding guess. State what you know, what you don't, and what you'd do — then let me decide when it matters.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- Prefer concise code snippets over descriptions of what the code should be.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
- Use the AskUserQuestion tool to resolve unresolved questions before finalizing the plan.
- Tests, linters, typecheckers, and build commands are non-destructive — run them in plan mode to verify errors without asking. Caveat: if a project's test/build command mutates shared state (e.g. shared dev DB, external API writes), treat it as destructive.

## Command Output

- Only save command output to a file when running tests, linters, or commands with known/potential failures. For simple commands (build, install, git, etc.) just run them directly.
- When saving output: `> ./tmp/output.txt 2>&1`, then process/query the file — never pipe long output inline or re-run commands to parse their output.
- Prefer `*:ai` versions of package.json scripts when available (e.g. `npm run lint:ai` not `npm run lint`).
- Run tests via project runners (e.g. NX), not directly via tool CLIs — runners set up necessary env vars.

## Delegation and agent spawning

- The lead's context window is scarce: delegate broad reading, searching, research, and self-contained implementation to agents; retain only distilled conclusions, paths, line references, and decisions. Do not accumulate raw file dumps or broad search output.
- **Multi-step or broad tasks go through my delegation workflow, not ad-hoc fan-out.** When orchestration is triggered — "ultracode", "use a workflow", or a task needing 2+ agents — run `Workflow({ scriptPath: "~/.claude/workflows/delegate.mjs", args: {...} })`. Never author a throwaway workflow script for this; `delegate.mjs` already encodes the policy (roles, one task per agent, concurrency cap 3, no worktrees for coding, distilled returns). Extend that file if it doesn't fit.
- `args` shape: `{ task, explore: [{name, prompt, isolate?}], implement: [{name, prompt, role?}], review?: true|string }`. Roles are `explore | implement | hard | plan | review | commit`.
- **Never pass `model` to `Agent` or `agent()`.** It is a closed enum and bypasses the configured gateway model. `subagent_type`/`agentType` is a role, never a model ID. Models come only from `~/.claude/agents/*.md` frontmatter. If the configured model is unavailable, report the failure rather than substituting one. Never put model IDs, `${VAR}`, `$VAR`, or `env:VAR` in agent prompts or frontmatter — setup bakes the tier in, and the registry loads at session start.
- When spawning `Agent` directly anyway (single scoped task, no workflow), it must still be a **named** teammate — a nameless/standalone spawn silently falls back to the session model.
- Be patient with team members, SPARK errors are temporary and will go away after a while - confirm with the user before killing/restarting any "failed" team member. It may just be slow.
- Invoke `tdd` when implementing code changes (not while planning); pass the relevant TDD instructions into implementation-agent prompts. Teammates execute only their assigned scope — they never invoke `tdd` and never spawn their own agents.
- Always delegate committing to a `custom-committer` teammate; never commit inline.

## Worktrees (CRITICAL)

- **Agents must NOT create worktrees, branches, or clones for coding work.** Implementation edits the working tree it was given. `isolation: 'worktree'` is never set for implementation agents. If an agent thinks isolation is required, it stops and says so rather than creating one.
- Temporary worktrees are allowed for **exploration or experimentation only**, and only when explicitly opted into (`isolate: true` in `delegate.mjs`, or my direct instruction). Every such worktree must be cleaned up — unchanged ones are auto-removed, and `cleanup-agent-worktrees.sh` sweeps the rest at SessionEnd.
- I may explicitly authorise a worktree for coding; that authorisation covers that one task only.

## Pull Requests

- After creating a PR with `gh pr create`, always immediately `open <pr-url>` to open it in the browser.

## Git Stash Safety (CRITICAL)

- **NEVER delete a stash if it fails to restore.** If `git stash pop` or `git stash apply` fails, STOP and have the user resolve it manually — the stash likely holds irreplaceable work. Applies to every agent; none may resolve a stash conflict autonomously.

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
