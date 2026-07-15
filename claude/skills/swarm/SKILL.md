---
name: swarm
description: Context-window delegation strategy for opus/opus-1m leads. Pushes raw reading/searching/self-contained implementation to cheap sub-agents so the lead never accumulates raw tokens — only conclusions. Use when planning any task, when codebase exploration is needed, when delegating sub-agents or teams, when controlling context window, when choosing model tiers, or when managing multi-stream work. DEFAULT when planning any task (alongside tdd for code tasks).
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

- Always when planning (this is a DEFAULT behavior alongside `/tdd` for code tasks)
- Any task requiring codebase exploration, multi-file reads, or research
- Any self-contained implementation work
- Any time ≥3 independent context-heavy streams exist

## Delegation triage

| Work type | Action |
|---|---|
| Exploration / search / research | **Always** `Explore` subagent — never grep/read widely as lead |
| Self-contained impl (clear inputs, scoped files, single deliverable) | `general-purpose` Agent |
| ≥3 independent, context-heavy streams | Team (cap 3–4 concurrent) |
| Tightly-coupled streams needing back-and-forth | No team — lead orchestrates sequentially |
| Trivial single-file lookup you already know the path to | Inline (don't over-delegate) |

## Two params on every Agent call

Every `Agent` call requires **two separate params**:

- `subagent_type` — the agent's **role**. Valid values: `general-purpose` (impl/edits), `Explore` (search/research), `Plan`, `claude`, `statusline-setup`. **NEVER a model ID here.**
- `model` — cheapest suitable tier (see below). **Always minimize.**

## Model tiers — cheapest suitable, always

| Model | Use for |
|---|---|
| `haiku` | Search, reads, scripts, simple edits, doc lookup |
| `sonnet` | Code editing, refactoring, new code, non-trivial test analysis |
| `opus` | Complex architecture, tricky multi-file refactors — **rare** |

Default to `haiku`. Upgrade only when the task clearly requires it.

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

- Lead grepping or reading files widely instead of delegating to `Explore`
- Passing a model ID (e.g. `"claude-sonnet-5"`) as `subagent_type`
- Giving an agent multiple unrelated tasks
- Defaulting to `opus` or `sonnet` when `haiku` suffices
- Agents returning raw file dumps instead of structured conclusions
- Delegating trivial lookups you already know the path to (overhead exceeds benefit)
