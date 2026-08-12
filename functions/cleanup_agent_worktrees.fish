function cleanup_agent_worktrees --description "Remove agent-* worktrees and their branches from the current git repo"
    # Require a normal repository or worktree, not a bare repository.
    if not _is_git_repo
        echo "Error: not a git repository" >&2
        return 1
    end

    set -l git_root (git rev-parse --show-toplevel 2>/dev/null)
    set -l git_common_dir (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if test -z "$git_root" -o -z "$git_common_dir" -o ! -d "$git_common_dir"
        echo "Error: could not resolve the Git repository" >&2
        return 1
    end

    # Refuse to run when HEAD is an agent-* branch; make no changes in that case.
    set -l current_branch (git -C $git_root symbolic-ref --short HEAD 2>/dev/null)
    if string match -q 'agent-*' -- $current_branch
        echo "Error: current branch '$current_branch' matches agent-*; switch away before cleaning" >&2
        return 1
    end

    # Collect registered worktrees checked out on local agent-* branches.
    set -l worktree_paths
    set -l worktree_branches
    set -l cur_path ""
    set -l cur_branch ""
    for line in (git -C $git_root worktree list --porcelain)
        set -l wt_match (string match -r '^worktree (.+)$' -- $line)
        set -l br_match (string match -r '^branch refs/heads/(.+)$' -- $line)
        if test -n "$wt_match"
            if test -n "$cur_path" -a -n "$cur_branch"; and string match -q 'agent-*' -- $cur_branch
                set -a worktree_paths $cur_path
                set -a worktree_branches $cur_branch
            end
            set cur_path $wt_match[2]
            set cur_branch ""
        else if test -n "$br_match"
            set cur_branch $br_match[2]
        end
    end
    if test -n "$cur_path" -a -n "$cur_branch"; and string match -q 'agent-*' -- $cur_branch
        set -a worktree_paths $cur_path
        set -a worktree_branches $cur_branch
    end

    set -l removed 0
    set -l failed 0
    for i in (seq 1 (count $worktree_paths))
        set -l wt_path $worktree_paths[$i]
        set -l branch $worktree_branches[$i]

        if git -C $git_root worktree remove --force $wt_path 2>/dev/null
            echo "removed worktree  $wt_path"
        else
            echo "warning: could not remove worktree '$wt_path'" >&2
            set failed (math $failed + 1)
        end

        if git -C $git_root branch -D $branch 2>/dev/null
            echo "deleted branch    $branch"
            set removed (math $removed + 1)
        else
            echo "warning: could not delete local branch '$branch'" >&2
            set failed (math $failed + 1)
        end
    end

    if git -C $git_root worktree prune 2>/dev/null
        echo "pruned stale worktree metadata"
    else
        echo "warning: could not prune stale worktree metadata" >&2
        set failed (math $failed + 1)
    end

    # Delete only local agent-* refs no longer registered to a worktree.
    set -l registered_branches
    for line in (git -C $git_root worktree list --porcelain)
        set -l br_match (string match -r '^branch refs/heads/(agent-.*)$' -- $line)
        if test -n "$br_match"
            set -a registered_branches $br_match[2]
        end
    end
    for branch in (git -C $git_root for-each-ref --format='%(refname:short)' 'refs/heads/agent-*')
        if not contains -- $branch $registered_branches
            if git -C $git_root branch -D $branch 2>/dev/null
                echo "deleted orphan branch  $branch"
                set removed (math $removed + 1)
            else
                echo "warning: could not delete orphan branch '$branch'" >&2
                set failed (math $failed + 1)
            end
        end
    end

    echo "done: $removed branch(es) removed"
    if test $failed -gt 0
        echo "      $failed failure(s) encountered (see warnings above)"
        return 1
    end
end
