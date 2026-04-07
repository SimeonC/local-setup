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

    set -l using_global_config 0
    if test -z "$config"
        set -l global_config "$HOME/.config/fish/claude/devcontainer/devcontainer.json"
        if test -f "$global_config"
            if set -q _flag_local
                echo "dco: no local config found, using global config"
            end
            set config $global_config
            set workspace $PWD
            set using_global_config 1
        else
            echo "dco: no devcontainer config found" >&2
            return 1
        end
    end

    # Auto-rebuild if global devcontainer config has changed since last build
    set -l hash_state_file ""
    if test $using_global_config -eq 1
        set -l dco_dir "$HOME/.config/fish/claude/devcontainer"
        set -l config_hash (find "$dco_dir" -maxdepth 1 -type f | sort | xargs cat 2>/dev/null | md5)
        set -l workspace_key (echo $workspace | md5)
        set -l hashes_dir "$dco_dir/.rebuild-hashes"
        mkdir -p $hashes_dir
        set hash_state_file "$hashes_dir/$workspace_key"
        if not set -q _flag_rebuild
            set -l stored_hash ""
            if test -f "$hash_state_file"
                set stored_hash (cat "$hash_state_file")
            end
            if test "$config_hash" != "$stored_hash"
                set_color --bold yellow
                echo "╔══════════════════════════════════════════╗"
                echo "║  🔄  devcontainer config changed         ║"
                echo "║      rebuilding automatically...         ║"
                echo "╚══════════════════════════════════════════╝"
                set_color normal
                set extra_args --remove-existing-container
            end
        end
    end

    # If workspace is a git worktree with absolute paths, convert to relative paths
    # so --mount-git-worktree-common-dir works correctly in the container
    set -l override_config_file ""
    if test -f "$workspace/.git"
        set -l gitdir_line (cat "$workspace/.git")
        set -l gitdir_path (string replace 'gitdir: ' '' -- $gitdir_line)
        if string match -q '/*' -- $gitdir_path
            echo "dco: converting worktree to relative paths"
            git -C $workspace worktree repair --relative-paths
            # Re-read after repair
            set gitdir_path (string replace 'gitdir: ' '' -- (cat "$workspace/.git"))
        end

        # When --mount-git-worktree-common-dir is used, the CLI mounts the common
        # ancestor of the workspace and gitdir at /workspaces/. The workspaceFolder
        # must match the nested path, not the flat basename.
        set -l levels_up 0
        set -l remaining $gitdir_path
        while string match -q '../*' -- $remaining
            set levels_up (math $levels_up + 1)
            set remaining (string replace -r '^\.\.\/' '' -- $remaining)
        end

        if test $levels_up -gt 1
            # CLI mounts N levels above workspace at /workspaces/
            set -l mount_root (realpath $workspace)
            for i in (seq $levels_up)
                set mount_root (dirname $mount_root)
            end
            set -l rel_path (string replace "$mount_root/" '' -- (realpath $workspace))
            # Generate modified config in a temp dir named devcontainer.json (CLI requires this name).
            # Patch workspaceFolder and make Dockerfile/context paths absolute so they
            # resolve correctly from the temp dir.
            set -l config_dir (realpath (dirname $config))
            set -l abs_context (realpath "$config_dir/../../..")
            set -l override_dir (mktemp -d /tmp/dco-override-XXXXXX)
            set override_config_file "$override_dir/devcontainer.json"
            sed \
                -e 's|"dockerfile": "Dockerfile"|"dockerfile": "'"$config_dir/Dockerfile"'"|' \
                -e 's|"context": "\.\./\.\./\.\."|"context": "'"$abs_context"'"|' \
                -e 's|/workspaces/\${localWorkspaceFolderBasename}|/workspaces/'"$rel_path"'|g' \
                $config > $override_config_file

            # The worktree parent dir contains all sibling repos — bind-mount it so
            # they are all visible at /workspaces/<parent>/ inside the container.
            set -l worktree_parent (dirname (realpath $workspace))
            set -l parent_name (basename $worktree_parent)
            set -a extra_args --mount "type=bind,source=$worktree_parent,target=/workspaces/$parent_name"
            echo "dco: nested worktree detected, workspaceFolder=/workspaces/$rel_path (siblings at /workspaces/$parent_name/)"
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

    # Forward terminal surface ID into the container so hooks can identify
    # which terminal tab owns this session.
    if set -q CMUX_SURFACE_ID
        set -a remote_env_args --remote-env "CMUX_SURFACE_ID=$CMUX_SURFACE_ID"
        if set -q CMUX_WORKSPACE_ID
            set -a remote_env_args --remote-env "CMUX_WORKSPACE_ID=$CMUX_WORKSPACE_ID"
        end
    else if set -q GHOSTTY_RESOURCES_DIR
        set -l term_uuid (osascript -e 'tell application "Ghostty" to return id of focused terminal of selected tab of front window' 2>/dev/null)
        if test -n "$term_uuid"
            set -a remote_env_args --remote-env "GHOSTTY_TERMINAL_UUID=$term_uuid"
            set -a remote_env_args --remote-env "GHOSTTY_RESOURCES_DIR=$GHOSTTY_RESOURCES_DIR"
        end
    end

    # Use override config if generated for nested worktrees
    set -l effective_config $config
    if test -n "$override_config_file"
        set effective_config $override_config_file
    end

    echo "dco: using $effective_config"
    devcontainer up --workspace-folder $workspace --config $effective_config \
        --mount-git-worktree-common-dir $extra_args
    or begin
        test -n "$override_config_file" && rm -rf (dirname $override_config_file)
        return $status
    end

    # Update rebuild hash after successful up (global config only)
    if test -n "$hash_state_file"
        set -l dco_dir "$HOME/.config/fish/claude/devcontainer"
        find "$dco_dir" -maxdepth 1 -type f | sort | xargs cat 2>/dev/null | md5 > $hash_state_file
    end

    devcontainer exec --workspace-folder $workspace --config $effective_config \
        $remote_env_args -- $cmd

    # Clean up temp override dir (not the original config)
    test -n "$override_config_file" && rm -rf (dirname $override_config_file)
end
