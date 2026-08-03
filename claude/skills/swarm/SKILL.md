---
name: swarm
description: Context-window delegation strategy. Pushes raw reading/searching/self-contained implementation to named sub-agents so the lead never accumulates raw tokens — only conclusions. Use when planning any task, when implementing a plan, when codebase exploration is needed, when delegating sub-agents or teams, when controlling context window, when routing sub-agent models, or when managing multi-stream work. DEFAULT both when planning any task AND when implementing a plan (alongside tdd for code tasks).
user_invocable: true
user_invocable_name: /swarm
---

# Swarm — Context-Controlled Delegation

$ARGUMENTS: optional focus or context for this swarm (e.g. "auth module refactor", "API research").

## Core principle

The lead's context window is the scarce resource. Raw file contents, search dumps, and intermediate data must never accumulate in the lead. Delegate all reading, searching, and self-contained work to sub-agents; receive back only distilled conclusions.

Lead holds: conclusions, paths, decisions, structured findings.
Lead never holds: raw file dumps, grep output, broad search results.

## When to invoke

- **Lead agents only**: Always when planning a task AND when implementing a plan (this is a DEFAULT behavior alongside `/tdd` for code tasks). Sub-agents should NOT invoke swarm — they ARE the delegation.
- Any task requiring codebase exploration, multi-file reads, or research
- Any self-contained implementation work
- Any time ≥3 independent context-heavy streams exist

## Delegation triage

| Work type | Action |
|---|---|
| Exploration / search / research | **Always** `explorer` subagent — never grep/read widely as lead |
| Self-contained impl (clear inputs, scoped files, single deliverable) | `worker` Agent |
| ≥3 independent, context-heavy streams | Team (cap 3–4 concurrent) |
| Tightly-coupled streams needing back-and-forth | No team — lead orchestrates sequentially |
| Committing | `committer` Agent — always delegate, never commit inline |
| Trivial single-file lookup you already know the path to | Inline (don't over-delegate) |

## Model routing (CRITICAL)

**Never pass the `model` param to `Agent`.** Its schema is a closed enum
(`sonnet | opus | haiku | fable`) and rejects custom gateway IDs client-side,
before the call reaches the gateway. Worse, when the enum *does* accept your
value it silently runs you off the configured model.

Model comes from **agent definitions only** — `~/.claude/agents/*.md` frontmatter
is the single source of truth. Route by picking a `subagent_type`; omit `model`.

| Agent | Model | Use |
|---|---|---|
| `explorer` | default tier | search, reads, research (read-only tools) |
| `worker` | default tier | **default** — impl, edits, tests |
| `committer` | default tier | staging + writing a single commit (no Edit/Write) |
| `specialist` | `claude-sonnet-4-6` | promotion tier — tricky refactors, subtle test analysis |
| `architect` | `claude-opus-5` | rare — design, multi-file architecture, chain-review orchestration |

"Default tier" is chosen per machine at setup time (`sh setup_agents.sh <model>`)
and baked into the generated agent files — frontmatter does not interpolate env
vars. Check the live value with `sed -n 's/^model: //p' ~/.claude/agents/worker.md`.

`worker` is the default tier: on this setup it is both cheapest *and* strong
enough for nearly everything. Promote to `specialist` or `architect` only when
the task clearly warrants it — not by habit.

`subagent_type` is the agent's **role**, never a model ID. The roster above plus
the stock roles (`general-purpose`, `Explore`, `Plan`, `claude`,
`statusline-setup`) are the valid values.

Verified: these agents resolve to their frontmatter model even when the parent
runs opus, and even against a differing `settings.json` default — the raw string
forwards to the gateway. Confirmed via `resolvedModel` in the Agent result
record, and via `claude -p --agent worker` at top level.

Three gotchas:

- `settings.json` sets a session default model, so subagents inherit it unless
  routed. The roster only *differs* from the default under another lead model.
- The agent registry loads at **session start**. A newly added or edited
  `agents/*.md` is invisible until a fresh session — it does not hot-reload.
  Same applies after re-running `setup_agents.sh`.
- Frontmatter `model:` is a literal string — `${VAR}`, `$VAR`, and `env:VAR`
  are all sent verbatim to the gateway and rejected. Never try to templatise it
  at runtime; regenerate the files instead.

## Single-task orientation

Each agent gets ONE scoped task. An implementation agent implements — it does NOT also run the full test suite, lint the repo, or touch unrelated areas. Verification, broad testing, and lint are **separate tasks** (separate agents or done by lead).

## Compact result contract

Instruct every sub-agent to return **distilled structured findings**: file paths, `file:line` references, conclusions, decisions. Not raw file contents. Not full search dumps. Cap output length. The lead synthesizes from summaries, not raw data.

Example instruction to include in agent prompts:
> Return only: file paths, line references, and 1–2 sentence conclusions per finding. Do not dump file contents.

## Teams & lifecycle

1. Cap 3–4 concurrent teammates.
2. Dismiss each on task completion: `SendMessage(to: "name", message: {type: "shutdown_request", reason: "..."})`. A friendly "you're done" does NOT terminate.
3. Loop: monitor → review → `TaskUpdate(status:"completed")` → dismiss → spawn next queued → repeat.
4. Never batch dismissals.
5. Before ending conversation: shutdown remaining, verify via `TaskList`, then `TeamDelete`.

## Anti-patterns

- Lead grepping or reading files widely instead of delegating to `explorer`
- Passing a model ID (e.g. `"claude-sonnet-5"`) as `subagent_type`
- Passing **any** `model` param — it either fails client-side or silently
  downgrades you off the configured model
- Naming a model anywhere outside `claude/agent_templates/*.md`
- Promoting to `specialist`/`architect` when `worker` suffices
- Giving an agent multiple unrelated tasks
- Agents returning raw file dumps instead of structured conclusions
- Delegating trivial lookups you already know the path to (overhead exceeds benefit)
