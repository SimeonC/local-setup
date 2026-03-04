function dco --description 'Start a devcontainer and run claude (or a custom command) in it'
    if not command -q devcontainer
        echo "dco: devcontainer CLI not found — install with: brew install devcontainer" >&2
        return 1
    end

    # Walk up directory tree to find .devcontainer.local/devcontainer.json
    set -l dir $PWD
    set -l config ""
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

    # Parse flags and collect remaining args as the exec command
    set -l extra_args
    set -l cmd
    for arg in $argv
        switch $arg
            case --rebuild
                set extra_args --remove-existing-container
            case '*'
                set -a cmd $arg
        end
    end

    # Default to interactive fish shell
    if test (count $cmd) -eq 0
        set cmd fish
    end

    # Advance the shared counter so container sessions continue the host's sequence
    set -l counter_file "$HOME/.claude/monitor_counter"
    set -l next 1
    if test -f "$counter_file"
        set next (math (cat "$counter_file") + 1)
    end
    echo $next >"$counter_file"
    set -gx CLAUDE_MONITOR_ID $next

    echo "dco: using $config"
    devcontainer up --workspace-folder $workspace --config $config $extra_args
    or return $status

    devcontainer exec --workspace-folder $workspace --config $config $cmd
end
