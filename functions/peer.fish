function peer --wraps=claude --description 'Claude with the local peer-programming plugin loaded'
    set -l plugin_dir "$HOME/.config/fish/claude-plugins/peer-programming"
    if not test -f "$plugin_dir/.claude-plugin/plugin.json"
        echo "Peer plugin not found at $plugin_dir; run setup.sh first." >&2
        return 1
    end

    # The peer mode always requires Claude. Save and restore the user's normal
    # backend around the existing wrapper so this invocation alone is forced.
    set -l had_global (set -qg AI_BACKEND; echo $status)
    set -l previous_backend $AI_BACKEND
    set -l exported_backend 0
    if set -qgx AI_BACKEND
        set exported_backend 1
    end
    set -gx AI_BACKEND claude

    claude $argv --plugin-dir "$plugin_dir"
    set -l result $status

    if test $had_global -eq 0
        if test $exported_backend -eq 1
            set -gx AI_BACKEND $previous_backend
        else
            set -ug AI_BACKEND $previous_backend
        end
    else
        # Erase only our global override so a universal value becomes visible again.
        set -ge AI_BACKEND
    end
    return $result
end
