function dco --description 'Start a devcontainer and run claude (or a custom command) in it'
    if not command -q devcontainer
        echo "dco: devcontainer CLI not found — install with: brew install devcontainer" >&2
        return 1
    end

    argparse 'rebuild' 'local' -- $argv
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

    set -l config ""
    set -l workspace ""

    if set -q _flag_local
        # Walk up directory tree to find .devcontainer/devcontainer.json
        set -l dir $PWD
        while true
            if test -f "$dir/.devcontainer/devcontainer.json"
                set config "$dir/.devcontainer/devcontainer.json"
                set workspace $dir
                break
            end
            set -l parent (dirname $dir)
            if test "$parent" = "$dir"
                break
            end
            set dir $parent
        end
    end

    if test -z "$config"
        set -l global_config "$HOME/.config/fish/claude/devcontainer/devcontainer.json"
        if test -f "$global_config"
            if set -q _flag_local
                echo "dco: no local config found, using global config"
            end
            set config $global_config
            set workspace $PWD
        else
            echo "dco: no devcontainer config found" >&2
            return 1
        end
    end

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

    # Run env setup (non-blocking) before container starts
    if test -f "$workspace/local_env.fish"
        echo "dco: running local_env.fish"
        source "$workspace/local_env.fish"
    end

    # Load .devcontainer/.env.local into remote env vars
    set -l remote_env_args
    if test -f "$workspace/.devcontainer/.env.local"
        echo "dco: loading .devcontainer/.env.local"
        while read -l line
            # Skip comments and blank lines
            string match -rq '^\s*(#|$)' -- $line; and continue
            set -a remote_env_args --remote-env $line
        end <"$workspace/.devcontainer/.env.local"
    end

    # Capture Ghostty terminal UUID on the host (osascript available here) so hooks
    # inside the container can identify which terminal tab owns this session.
    if set -q GHOSTTY_RESOURCES_DIR
        set -l term_uuid (osascript -e 'tell application "Ghostty" to return id of focused terminal of selected tab of front window' 2>/dev/null)
        if test -n "$term_uuid"
            set -a remote_env_args --remote-env "GHOSTTY_TERMINAL_UUID=$term_uuid"
        end
    end

    echo "dco: using $config"
    devcontainer up --workspace-folder $workspace --config $config \
        --mount-git-worktree-common-dir $extra_args
    or return $status

    devcontainer exec --workspace-folder $workspace --config $config \
        $remote_env_args -- $cmd
end
