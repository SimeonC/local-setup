---
name: worktree-cleanup
description: Clean up a worktree set created by /worktree-setup. All sets live under ~/Development/.worktrees/ as wrapper folders. Removes git worktrees from each source repo, deletes the wrapper folder, and never touches the shared .worktrees/ parent.
user_invocable: true
user_invocable_name: /worktree-cleanup
---

# Worktree Cleanup

Removes a worktree set created by `/worktree-setup`.

All sets live under `~/Development/.worktrees/<wrapper>/` — the wrapper is either `<repo>-<feature>` (single-repo) or `<feature>` (multi-repo). The shared `~/Development/.worktrees/` parent is never deleted.

## Steps

### 1. Identify Worktree Set

List all existing wrapper folders:
```bash
ls ~/Development/.worktrees/
```

If the user provides a feature name, find the matching wrapper. Otherwise show all found wrappers and ask which to clean up.

Read `CLAUDE.md` inside the target wrapper to discover:
- Which repos are included and their worktree subpaths
- The port block assigned to this set

### 2. Confirm With User

Show what will be removed:
- The wrapper folder and all its contents
- The git worktree references in each source repo
- The branches (ask whether to delete or keep them)

**Always confirm before proceeding.** This is destructive.

### 3. Remove Git Worktrees

For each repo listed in the wrapper's CLAUDE.md, use the path recorded there:

```bash
cd ~/Development/<repo>
git worktree remove ~/Development/.worktrees/<wrapper>/<repo>
```

- If removal fails due to uncommitted changes, warn the user and ask whether to force (`--force`) or skip
- If the user chose to delete branches too:

```bash
git branch -d <feature>
```

Use `-d` (safe delete) not `-D`. If the branch has unmerged changes, warn and ask before force-deleting.

### 4. Remove Wrapper Folder

After all git worktrees are removed, delete only the wrapper folder — never the shared parent:

```bash
rm -rf ~/Development/.worktrees/<wrapper>/
```

Do **not** delete `~/Development/.worktrees/` itself.

### 5. Summary

Print what was cleaned up:
- Worktrees removed
- Branches deleted or kept
- Port block freed (mention the range so user knows it's available again for the next `/worktree-setup`)
