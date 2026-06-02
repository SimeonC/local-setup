function _is_git_repo
    # Returns 0 (true) if dir is a git repo or worktree (.git file or dir).
    # Usage: _is_git_repo [dir]  — defaults to $PWD
    set -l dir
    if test (count $argv) -gt 0
        set dir $argv[1]
    else
        set dir $PWD
    end
    git -C $dir rev-parse --git-dir >/dev/null 2>&1
end
