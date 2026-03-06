---
name: worktree-setup
description: Set up multi-repo worktree folders for feature development. Creates a shared worktree directory with git worktrees for multiple repositories, a root CLAUDE.md with port assignments, and folder conventions so work can happen alongside normal development.
user_invocable: true
user_invocable_name: /worktree-setup
---

# Multi-Repo Worktree Setup

Sets up a worktree folder at `~/Development/<feature>-wts/` containing git worktrees for multiple repositories, with unique port assignments and a root CLAUDE.md.

## Steps

### 1. Gather Information

Ask the user (use AskUserQuestion):

1. **Feature name** — used for the folder name and branch names (e.g. `free-sizing`)
2. **Repositories** — which repos to include. List folders found in `~/Development/` that are git repos and let the user pick. Allow free-text too for repos not yet cloned.

### 2. Create Worktree Folder

```
~/Development/<feature>-wts/
```

### 3. Allocate Port Block

Each worktree set gets a unique port block to avoid clashes with normal dev and other worktree sets.

- Scan `~/Development/*-wts/CLAUDE.md` files to find already-allocated port blocks
- Base range starts at **4000**, each block is **100 ports wide** (4000-4099, 4100-4199, etc.)
- Pick the next unallocated block
- Within the block, assign ports to repos in order (first repo gets base+0, second gets base+10, etc. — 10 ports per repo allows for multiple services per repo)

### 4. Create Git Worktrees

For each selected repository:

```bash
cd ~/Development/<repo>
git fetch origin
git worktree add --relative-paths ~/Development/<feature>-wts/<repo> -b <feature> origin/main
```

- Branch name: `<feature>` (same as the feature name)
- Based on: `origin/main` (fetched fresh)
- If the branch already exists, use `git worktree add --relative-paths ~/Development/<feature>-wts/<repo> <feature>` instead

### 5. Generate Root CLAUDE.md

Create `~/Development/<feature>-wts/CLAUDE.md` with:

```markdown
# <Feature> Worktree

Feature: <feature>
Port block: <base>-<base+99>

## Repositories

| Repo | Path | Port Range | Branch |
|------|------|------------|--------|
| <repo1> | ./<repo1> | <base>-<base+9> | <feature> |
| <repo2> | ./<repo2> | <base+10>-<base+19> | <feature> |
| ... | ... | ... | ... |

## Port Assignments

Each repo gets 10 ports starting from its base. Use these instead of default ports
to avoid clashing with normal development running in ~/Development/<repo>.

When configuring services, override port settings to use the assigned range above.

## Working With This Worktree

- Each subfolder is a git worktree of the corresponding repo in ~/Development/
- Commits and branches are shared with the main repo checkout
- Run `git worktree remove <path>` from the main repo to clean up
- To remove this entire worktree set: run cleanup from each main repo, then delete this folder
```

### 7. Summary

Print a summary of what was created:
- Folder path
- Repos and their worktree paths
- Port assignments
- How to start working: `cd ~/Development/<feature>-wts && dco`

## Important Notes

- Always `git fetch origin` before creating worktrees to ensure main is up to date
- If a worktree folder already exists, warn the user and ask before overwriting
- The CLAUDE.md at the root is critical — it's what lets Claude understand the multi-repo setup when working inside the worktree folder
