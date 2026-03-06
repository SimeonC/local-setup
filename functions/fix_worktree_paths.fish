function fix_worktree_paths --description 'Convert all git worktrees to relative paths'
    set -l base_dir $argv[1]
    test -z "$base_dir" && set base_dir ~/Development

    # Find main repos that have worktrees
    for git_dir in $base_dir/*/.git
        test -d "$git_dir" || continue # skip worktree .git files
        set -l repo (dirname $git_dir)
        set -l wt_dir "$git_dir/worktrees"
        test -d "$wt_dir" || continue # skip repos without worktrees
        echo "Fixing: $repo"
        git -C $repo worktree repair --relative-paths
    end
end
