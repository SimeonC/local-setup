#!/usr/bin/env bash
# Claude Code WorktreeCreate hook.
# Places worktrees at ~/Development/worktrees/<repo>/<name> instead of .claude/worktrees/.
# Contract: reads hook JSON on stdin; must print the created worktree path as the
# last non-empty stdout line. Any non-zero exit aborts worktree creation.
set -euo pipefail

input=$(cat)
name=$(printf '%s' "$input" | jq -r '.name // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

[ -n "$cwd" ] || cwd="$PWD"
[ -n "$name" ] || name="worktree"

repo_root=$(git -C "$cwd" rev-parse --show-toplevel)
repo=$(basename "$repo_root")

base_dir="$HOME/Development/worktrees/$repo"
mkdir -p "$base_dir"

# Honor worktree.baseRef: fresh -> branch from origin's default branch.
# (No fetch: uses the already-known origin/HEAD to stay fast and offline-safe.)
default_ref=$(git -C "$repo_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
if [ -z "$default_ref" ]; then
  git -C "$repo_root" remote set-head origin --auto >/dev/null 2>&1 || true
  default_ref=$(git -C "$repo_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
fi
base=${default_ref:-HEAD}

# Ensure a unique branch name + destination directory (avoids collisions when a
# name is reused across sessions or repos).
branch="$name"
dest="$base_dir/$branch"
i=2
while git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" || [ -e "$dest" ]; do
  branch="$name-$i"
  dest="$base_dir/$branch"
  i=$((i + 1))
done

git -C "$repo_root" worktree add -b "$branch" "$dest" "$base" >&2

printf '%s\n' "$dest"
