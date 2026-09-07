---
name: commit
description: Stage changes and write ONE commit in the repo's convention. Use PROACTIVELY for every commit — whenever the user asks to commit, save work, or you have finished a unit of work that should be committed.
argument-hint: [optional scope or message hint]
---

# Commit

Stage changes and create ONE commit. Do not write, edit, or refactor code as
part of this — a commit records work that is already done.

## Procedure

1. Inspect state: `git status`, `git diff`, `git diff --staged`, and
   `git log --oneline -15` for the existing convention.
2. Determine the convention from repo documentation first (`CONTRIBUTING.md`,
   `.gitmessage`, commit-lint config). Only fall back to `git log` if no docs
   exist, and only if the log is consistent. Otherwise use gitmoji.
3. Stage the intended changes and commit.

## Convention

Gitmoji style unless the repo documents otherwise — e.g.
`🐛 Fix race condition in session cleanup`, `✨ Add pr_ai command`.
Subject line only unless the change genuinely needs a body. Describe what
changed and why, not which files.

Common gitmoji:

- New feature: `✨ Add ...`
- Bug fix: `🐛 Fix ...`
- Refactor: `♻️ Refactor ...`
- Tests only: `✅ Add tests for ...`
- Types/config: `🏗️ Update ...`
- Removal: `🔥 Remove ...`

## Hard rules

- **Never delete, drop, or overwrite a stash.** If `git stash pop`/`apply`
  fails, STOP and report it for manual resolution — the stash may hold
  irreplaceable user work. Never resolve a stash conflict autonomously.
- Never `push`, never `commit --amend` an already-pushed commit, never
  `rebase`, `reset --hard`, or force-push unless explicitly instructed.
- Never skip pre-commit hooks (no `--no-verify`). If a hook rejects the commit,
  fix the underlying lint/type/format/test failure and retry.
- Do not commit files that look unintended (secrets, large binaries, `.env`,
  editor cruft). Flag them instead of staging them.
- One commit per invocation. Do not run tests, lint, or open a PR.

## Return

Report ONLY: the commit SHA, the subject line, and a one-line note of anything
deliberately left unstaged. No diffs, no file dumps.
