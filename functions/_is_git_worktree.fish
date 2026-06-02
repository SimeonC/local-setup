function _is_git_worktree
    # Returns 0 (true) if dir is a git worktree (has .git as a file, not a directory).
    # Usage: _is_git_worktree [dir]  — defaults to $PWD
    set -l dir
    if test (count $argv) -gt 0
        set dir $argv[1]
    else
        set dir $PWD
    end
    test -f "$dir/.git"
end
