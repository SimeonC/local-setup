function dco --description 'Start a devcontainer and run claude (or a custom command) in it'
    if not command -q devcontainer
        echo "dco: devcontainer CLI not found — install with: brew install devcontainer" >&2
        return 1
    end

    argparse 'rebuild' -- $argv
    or return 1

    set -l extra_args
    if set -q _flag_rebuild
        set extra_args --remove-existing-container
    end

    # Build the exec command: no args → fish, args → fish -C '<args>'
    set -l cmd
    if test (count $argv) -eq 0
        set cmd fish
    else
        set cmd fish -C "$argv"
    end

    # Walk up directory tree to find .devcontainer.local/devcontainer.json
    set -l dir $PWD
    set -l config ""
    set -l workspace ""
    while true
        if test -f "$dir/.devcontainer.local/devcontainer.json"
            set config "$dir/.devcontainer.local/devcontainer.json"
            set workspace $dir
            break
        end
        set -l parent (dirname $dir)
        if test "$parent" = "$dir"
            break
        end
        set dir $parent
    end

    if test -z "$config"
        set -l global_config "$HOME/.config/fish/claude/devcontainer/devcontainer.json"
        if test -f "$global_config"
            echo "dco: no local config found, using global config"
            set config $global_config
            set workspace $PWD
        else
            echo "dco: no .devcontainer.local/devcontainer.json found in $PWD or any parent directory" >&2
            return 1
        end
    end

    # Advance the shared counter so container sessions continue the host's sequence
    set -l counter_file "$HOME/.claude/monitor_counter"
    set -l next 1
    if test -f "$counter_file"
        set next (math (cat "$counter_file") + 1)
    end
    echo $next >"$counter_file"
    set -gx CLAUDE_MONITOR_ID $next

    # If workspace is a git worktree with absolute paths, convert to relative paths
    # so --mount-git-worktree-common-dir works correctly in the container
    if test -f "$workspace/.git"
        set -l gitdir_line (cat "$workspace/.git")
        set -l gitdir_path (string replace 'gitdir: ' '' -- $gitdir_line)
        if string match -q '/*' -- $gitdir_path
            echo "dco: converting worktree to relative paths"
            git -C $workspace worktree repair --relative-paths
        end
    end

    echo "dco: using $config"
    devcontainer up --workspace-folder $workspace --config $config \
        --mount-git-worktree-common-dir $extra_args
    or return $status

    devcontainer exec --workspace-folder $workspace --config $config -- $cmd
end
