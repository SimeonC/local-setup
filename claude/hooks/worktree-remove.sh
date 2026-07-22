#!/usr/bin/env bash
# Claude Code WorktreeRemove hook.
# Cleans up a worktree created by worktree-create.sh (and its branch, matching the
# built-in "remove" semantics). Removal intent is already gated by ExitWorktree,
# which refuses to call this on a dirty worktree unless discard_changes was set.
# Contract: reads hook JSON on stdin; output is not parsed. Never fail the session.
set -euo pipefail

input=$(cat)
wt=$(printf '%s' "$input" | jq -r '.worktree_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

[ -n "$wt" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

git -C "$cwd" worktree remove --force "$wt" >/dev/null 2>&1 || exit 0

# Branch name matches the worktree dir basename (see worktree-create.sh).
branch=$(basename "$wt")
git -C "$cwd" branch -D "$branch" >/dev/null 2>&1 || true
