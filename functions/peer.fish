function peer --wraps=claude --description 'Claude with the local peer-programming plugin loaded'
    set -l plugin_dir "$HOME/.config/fish/claude-plugins/peer-programming"
    if not test -f "$plugin_dir/.claude-plugin/plugin.json"
        echo "Peer plugin not found at $plugin_dir; run setup.sh first." >&2
        return 1
    end

    claude $argv --plugin-dir "$plugin_dir"
end
