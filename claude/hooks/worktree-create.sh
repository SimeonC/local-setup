#!/usr/bin/env bash
# Claude Code WorktreeCreate hook.
set -euo pipefail
input=$(cat)
name=$(printf '%s' "$input" | jq -r '.name // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$name" ] || name="worktree"
repo_root=$(git -C "$cwd" rev-parse --show-toplevel)
repo=$(basename "$repo_root")
base_dir="$HOME/Development/.worktrees/$repo"
mkdir -p "$base_dir"
default_ref=$(git -C "$repo_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@') || true
if [ -z "$default_ref" ]; then
  git -C "$repo_root" remote set-head origin --auto >/dev/null 2>&1 || true
default_ref=$(git -C "$repo_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@') || true
fi
base=${default_ref:-HEAD}
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
