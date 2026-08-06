#!/usr/bin/env bash
# Claude Code WorktreeRemove hook and shared cleanup helper.
# Usage: worktree-remove.sh [path], or pass hook JSON on stdin.
set -uo pipefail

cleanup_worktree() {
    local wt="$1"
    [ -n "$wt" ] || return 0
    [ -e "$wt" ] || [ -d "$wt" ] || return 0

    local common_dir repo_dir branch
    common_dir=$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null) || return 0
    repo_dir=$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null) || return 0
    branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$branch" ] || return 0
    git -C "$repo_dir" worktree remove --force -- "$wt" >/dev/null 2>&1 || return 0
    git --git-dir="$common_dir" branch -D -- "$branch" >/dev/null 2>&1 || true
}

if [ "$#" -gt 0 ]; then
    cleanup_worktree "$1"
    exit 0
fi
input=$(cat)
wt=$(printf '%s' "$input" | jq -r '.worktree_path // empty' 2>/dev/null || true)
cleanup_worktree "$wt"
exit 0
