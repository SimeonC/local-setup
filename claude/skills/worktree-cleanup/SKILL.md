---
name: worktree-cleanup
description: Clean up a multi-repo worktree folder created by /worktree-setup. Removes git worktrees from each source repo and deletes the worktree folder.
user_invocable: true
user_invocable_name: /worktree-cleanup
---

# Multi-Repo Worktree Cleanup

Removes a worktree set created by `/worktree-setup`.

## Steps

### 1. Identify Worktree Set

- If the user provides a feature name, target `~/Development/<feature>-wts/`
- If not, list existing `~/Development/*-wts/` folders and ask which to clean up
- Read the `CLAUDE.md` in the target folder to understand which repos are included

### 2. Confirm With User

Show what will be removed:
- The worktree folder and all its contents
- The git worktree references in each source repo
- The branches (ask whether to delete or keep them)

**Always confirm before proceeding.** This is destructive.

### 3. Remove Git Worktrees

For each repo listed in the worktree set's CLAUDE.md:

```bash
cd ~/Development/<repo>
git worktree remove ~/Development/<feature>-wts/<repo>
```

- If removal fails due to uncommitted changes, warn the user and ask whether to force (`--force`) or skip
- If the user chose to delete branches too:

```bash
git branch -d <feature>
```

Use `-d` (safe delete) not `-D`. If the branch has unmerged changes, warn and ask before force-deleting.

### 4. Remove Worktree Folder

After all git worktrees are removed, delete the now-empty folder:

```bash
rm -rf ~/Development/<feature>-wts/
```

### 5. Summary

Print what was cleaned up:
- Worktrees removed
- Branches deleted or kept
- Port block freed (mention the range so user knows it's available again)
