---
name: worktree-cleanup
description: Clean up a worktree folder created by /worktree-setup. Handles both single-repo (~/Development/.worktrees/<repo>-<feature>/) and multi-repo (~/Development/<feature>-wts/) layouts. Removes git worktrees from each source repo and deletes the worktree folder.
user_invocable: true
user_invocable_name: /worktree-cleanup
---

# Worktree Cleanup

Removes a worktree set created by `/worktree-setup`. Handles both layouts:

- **Single-repo** — `~/Development/.worktrees/<repo>-<feature>/`
- **Multi-repo** — `~/Development/<feature>-wts/`

## Steps

### 1. Identify Worktree Set

List all existing worktree sets from both layouts:
- `~/Development/*-wts/` (multi-repo sets)
- `~/Development/.worktrees/*/` (single-repo sets)

If the user provides a feature name, find the matching set. Otherwise show all found sets and ask which to clean up.

Read the `CLAUDE.md` in the target folder to discover:
- Which repos are included and their worktree paths
- The port block assigned to this set

### 2. Confirm With User

Show what will be removed:
- The worktree folder and all its contents
- The git worktree references in each source repo
- The branches (ask whether to delete or keep them)

**Always confirm before proceeding.** This is destructive.

### 3. Remove Git Worktrees

For each repo listed in the worktree set's CLAUDE.md, use the path recorded there:

**Single-repo mode:**
```bash
cd ~/Development/<repo>
git worktree remove ~/Development/.worktrees/<repo>-<feature>
```

**Multi-repo mode:**
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

After all git worktrees are removed, delete only the specific feature folder:

**Single-repo mode** — delete just the feature worktree, never the shared parent:
```bash
rm -rf ~/Development/.worktrees/<repo>-<feature>/
```
Do **not** delete `~/Development/.worktrees/` itself — it is shared across all single-repo worktree sets.

**Multi-repo mode:**
```bash
rm -rf ~/Development/<feature>-wts/
```

### 5. Summary

Print what was cleaned up:
- Worktrees removed
- Branches deleted or kept
- Port block freed (mention the range so user knows it's available again for the next `/worktree-setup`)
