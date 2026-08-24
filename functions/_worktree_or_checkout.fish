function _worktree_or_checkout --description 'Leave CWD at the working location for <head-branch>; worktree or checkout as needed'
    # Usage: _worktree_or_checkout <head-branch> [pr-number]
    # Leaves the shell's CWD at the correct working location for <head> and
    # returns non-zero on failure. fish `cd` is process-global, so the caller
    # continues in the new directory.
    if test (count $argv) -lt 1
        echo "❌ _worktree_or_checkout: <head-branch> required." >&2
        return 1
    end
    set -l head $argv[1]
    set -l number ''
    if test (count $argv) -ge 2
        set number $argv[2]
    end

    if not _is_git_repo
        echo "❌ Not inside a git repository." >&2
        return 1
    end

    # --- 1. Best-effort fetch ---------------------------------------------
    git fetch origin $head 2>/dev/null

    # --- 2. Already on the head branch --------------------------------
    # Compare by origin name, not the raw local name: a local branch like
    # `theme/details-styling-refactor` tracking `origin/details-styling-refactor`
    # IS the `details-styling-refactor` branch, so no prompt/worktree is needed.
    set -l current (_current_origin_branch)
    if test "$current" = "$head"
        echo "📥 On branch '$head' — syncing..."
        if not git merge --ff-only @{u} 2>/dev/null
            echo "⚠️  Could not fast-forward (local commits or divergence). Continuing without sync." >&2
        end
        return 0
    end

    # --- 3. Already checked out in another worktree -----------------------
    # An existing worktree just becomes an extra entry in the single chooser
    # below, so the user picks the working location in one step.
    set -l existing_path ''
    set -l wt_existing (git worktree list --porcelain | string match -e -- "branch refs/heads/$head")
    if test -n "$wt_existing"
        # Find the worktree path preceding the matching branch line.
        set existing_path (git worktree list --porcelain | awk -v b="refs/heads/$head" '
            /^worktree / { p = substr($0, 10) }
            $0 == "branch " b { print p; exit }')
    end

    # --- 4. Choose the working location ------------------------------------
    set -l repo (basename (git rev-parse --show-toplevel))
    set -l parent ~/Development/.worktrees/$repo

    if not command -q gum
        echo "❌ 'gum' is not installed (brew install gum)." >&2
        return 1
    end

    set -l opts
    test -n "$existing_path"; and set -a opts "Reuse existing worktree — $existing_path"
    set -a opts "New worktree — $parent/$head"
    set -a opts "Checkout here — "(pwd)

    # gum exits non-zero on Esc / Ctrl-C.
    set -l choice (gum choose --header "Branch is '$head', you're on '$current' — where should the work happen?" $opts)
    or return 1

    switch $choice
        case 'Reuse *'
            cd $existing_path; or return 1
            if not git merge --ff-only @{u} 2>/dev/null
                echo "⚠️  Could not fast-forward existing worktree. Continuing without sync." >&2
            end
            echo "📂 Working in: $existing_path"
            return 0
        case 'New worktree*'
            mkdir -p $parent
            set -l dest $parent/$head
            # If dest exists but isn't a registered worktree, suffix -2, -3, ...
            if test -e $dest
                set -l dest_real (realpath $dest 2>/dev/null)
                if not git worktree list --porcelain | string match -q -- "worktree $dest_real"
                    set -l n 2
                    while test -e $parent/$head-$n
                        set n (math $n + 1)
                    end
                    set dest $parent/$head-$n
                end
            end
            if test -n "$number"
                if not git worktree add $dest --detach
                    echo "❌ Failed to create worktree at $dest" >&2
                    return 1
                end
                cd $dest; or return 1
                if not gh pr checkout $number
                    echo "❌ Failed to check out PR #$number in worktree." >&2
                    return 1
                end
            else
                if not git worktree add $dest $head
                    echo "❌ Failed to create worktree at $dest" >&2
                    return 1
                end
                cd $dest; or return 1
            end
            echo "📂 Working in worktree: $dest"
            return 0
        case 'Checkout *'
            set -l dirty (git status --porcelain)
            if test -n "$dirty"
                echo "❌ Working tree is dirty — cannot checkout. Re-run and choose worktree, or `git stash` first." >&2
                return 1
            end
            if test -n "$number"
                gh pr checkout $number; or return 1
            else
                git switch $head; or return 1
            end
            return 0
        case '*'
            echo "❌ Unknown choice '$choice' — aborting." >&2
            return 1
    end
end
