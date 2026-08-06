#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
export HOME="$root/home"; mkdir -p "$HOME"
repo="$root/repo with spaces"; mkdir -p "$repo"; git -C "$repo" init -q; git -C "$repo" config user.email test@example.com; git -C "$repo" config user.name test; touch "$repo/file"; git -C "$repo" add .; git -C "$repo" commit -qm init
create="$OLDPWD/claude/hooks/worktree-create.sh"; remove="$OLDPWD/claude/hooks/worktree-remove.sh"
p=$(printf '%s' "{\"name\":\"agent-test\",\"cwd\":\"$repo\"}" | bash "$create"); test -d "$p"; test "$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" -eq 2
printf '%s' "{\"worktree_path\":\"$p\",\"cwd\":\"$repo\"}" | bash "$remove"; test ! -e "$p"; ! git -C "$repo" show-ref --verify --quiet refs/heads/agent-test
bash "$remove" <<< "{\"worktree_path\":\"$p\"}"
p=$(printf '%s' "{\"name\":\"agent-test\",\"cwd\":\"$repo\"}" | bash "$create"); p2=$(printf '%s' "{\"name\":\"agent-test\",\"cwd\":\"$repo\"}" | bash "$create"); [[ "$p2" == *agent-test-2 ]]; bash "$remove" "$p"; bash "$remove" "$p2"
git -C "$repo" worktree add "$root/non-agent" >/dev/null; test -d "$root/non-agent"; git -C "$repo" worktree remove --force "$root/non-agent" >/dev/null
printf 'worktree hook tests passed\n'
