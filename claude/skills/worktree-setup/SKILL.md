---
name: worktree-setup
description: Set up worktree folders for feature development. For a single repo, creates a flat worktree under ~/Development/.worktrees/. For multiple repos, creates a shared ~/Development/<feature>-wts/ folder. Assigns unique port blocks and generates a root CLAUDE.md.
user_invocable: true
user_invocable_name: /worktree-setup
---

# Worktree Setup

Sets up git worktrees for feature development with unique port assignments and a root CLAUDE.md.

- **Single repo (1)** — `~/Development/.worktrees/<repo>-<feature>/`
- **Multi-repo (≥2)** — `~/Development/<feature>-wts/<repo>/` (one subfolder per repo)

Mode is auto-detected from the number of repos selected in step 1.

## Steps

### 1. Gather Information

Ask the user (use AskUserQuestion):

1. **Feature name** — used for folder and branch names (e.g. `free-sizing`)
2. **Repositories** — which repos to include. List folders found in `~/Development/` that are git repos and let the user pick. Allow free-text too for repos not yet cloned.

After the user responds, determine the mode:
- 1 repo selected → **single-repo mode**
- ≥2 repos selected → **multi-repo mode**

### 2. Create Worktree Folder

**Single-repo mode:**
```bash
mkdir -p ~/Development/.worktrees
```
The worktree itself will be created at `~/Development/.worktrees/<repo>-<feature>/` in step 4.

**Multi-repo mode:**
```bash
mkdir -p ~/Development/<feature>-wts
```

### 3. Allocate Port Block

Each worktree set gets a unique port block to avoid clashes with normal dev and other worktree sets.

- Scan **both** of the following for already-allocated port blocks:
  - `~/Development/*-wts/CLAUDE.md` (multi-repo sets)
  - `~/Development/.worktrees/*/CLAUDE.md` (single-repo sets)
- Base range starts at **4000**, each block is **100 ports wide** (4000-4099, 4100-4199, etc.)
- Pick the next unallocated block
- Within the block, assign ports to repos in order (first repo gets base+0, second gets base+10, etc. — 10 ports per repo allows for multiple services per repo)

### 4. Create Git Worktrees

**Single-repo mode** — target path is `~/Development/.worktrees/<repo>-<feature>`:
```bash
cd ~/Development/<repo>
git fetch origin
git worktree add ~/Development/.worktrees/<repo>-<feature> -b <feature> origin/main
```

**Multi-repo mode** — target path is `~/Development/<feature>-wts/<repo>`:
```bash
cd ~/Development/<repo>
git fetch origin
git worktree add ~/Development/<feature>-wts/<repo> -b <feature> origin/main
```

- Branch name: `<feature>` (same as the feature name)
- Based on: `origin/main` (fetched fresh)
- If the branch already exists, omit `-b <feature>` from the command

### 5. Generate Root CLAUDE.md

**Single-repo mode** — write to `~/Development/.worktrees/<repo>-<feature>/CLAUDE.md`:

```markdown
# <Feature> Worktree

Feature: <feature>
Port block: <base>-<base+9>

## Repositories

| Repo | Path | Port Range | Branch |
|------|------|------------|--------|
| <repo> | . | <base>-<base+9> | <feature> |

## Port Assignments

This repo gets 10 ports starting from <base>. Use these instead of default ports
to avoid clashing with normal development running in ~/Development/<repo>.

When configuring services, override port settings to use the assigned range above.

## Working With This Worktree

- This folder is a git worktree of ~/Development/<repo>
- Commits and branches are shared with the main repo checkout
- Run `git worktree remove <path>` from the main repo to clean up
- To remove this worktree: run /worktree-cleanup
```

**Multi-repo mode** — write to `~/Development/<feature>-wts/CLAUDE.md`:

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
- To remove this entire worktree set: run /worktree-cleanup
```

### 7. Summary

Print a summary of what was created:
- Layout mode (single-repo or multi-repo)
- Worktree path(s)
- Port assignments
- How to start working:
  - Single-repo: `cd ~/Development/.worktrees/<repo>-<feature>`
  - Multi-repo: `cd ~/Development/<feature>-wts && dco`

## Important Notes

- Always `git fetch origin` before creating worktrees to ensure main is up to date
- If a worktree folder already exists, warn the user and ask before overwriting
- The CLAUDE.md at the worktree root is critical — it's what lets Claude understand the setup when working inside the worktree folder
