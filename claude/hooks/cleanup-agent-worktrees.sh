#!/usr/bin/env bash
# Claude Code SessionEnd hook — remove clean agent-* worktrees automatically.
# Dirty worktrees (uncommitted changes or unpushed commits on the agent branch) are
# skipped and reported to stderr so the user knows they need manual attention.
#
# Reads hook JSON from stdin; uses .cwd to locate the repo.
set -uo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$CWD" ] || CWD="$PWD"

# Resolve the common git dir for this repo (works inside any worktree too).
COMMON_DIR=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

removed=0
skipped=0

maybe_remove() {
    local wt="$1" branch="$2"
    [ -d "$wt" ] || return 0

    # Skip if the worktree has uncommitted changes.
    if ! git -C "$wt" diff --quiet 2>/dev/null || ! git -C "$wt" diff --cached --quiet 2>/dev/null; then
        echo "cleanup-agent-worktrees: skipping dirty worktree $wt (uncommitted changes)" >&2
        skipped=$((skipped + 1))
        return 0
    fi

    # Skip if the agent branch has commits not reachable from origin/HEAD.
    local base
    base=$(git -C "$REPO_ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@') || true
    if [ -n "$base" ]; then
        local ahead
        ahead=$(git -C "$REPO_ROOT" rev-list --count "refs/remotes/$base..refs/heads/$branch" 2>/dev/null || echo "")
        if [[ -n "$ahead" && "$ahead" -gt 0 ]]; then
            echo "cleanup-agent-worktrees: skipping $wt ($branch has $ahead unpushed commit(s))" >&2
            skipped=$((skipped + 1))
            return 0
        fi
    fi

    if git -C "$REPO_ROOT" worktree remove --force -- "$wt" >/dev/null 2>&1; then
        git --git-dir="$COMMON_DIR" branch -D -- "$branch" >/dev/null 2>&1 || true
        removed=$((removed + 1))
    else
        echo "cleanup-agent-worktrees: failed to remove worktree $wt" >&2
        skipped=$((skipped + 1))
    fi
}

# Parse `git worktree list --porcelain` to find agent-* worktrees.
cur_path=""
cur_branch=""
while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]](.+)$ ]]; then
        if [[ -n "$cur_path" && "$cur_branch" == agent-* ]]; then
            maybe_remove "$cur_path" "$cur_branch"
        fi
        cur_path="${BASH_REMATCH[1]}"
        cur_branch=""
    elif [[ "$line" =~ ^branch[[:space:]]refs/heads/(.+)$ ]]; then
        cur_branch="${BASH_REMATCH[1]}"
    fi
done < <(git -C "$REPO_ROOT" worktree list --porcelain)
# Handle the last entry.
if [[ -n "$cur_path" && "$cur_branch" == agent-* ]]; then
    maybe_remove "$cur_path" "$cur_branch"
fi

# Prune stale metadata regardless.
git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

[ "$skipped" -gt 0 ] && echo "cleanup-agent-worktrees: $skipped dirty worktree(s) skipped — remove manually" >&2
exit 0
