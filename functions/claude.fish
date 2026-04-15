function claude --wraps=claude --description 'Claude Code with tmux session management'
    # Pass-through for non-interactive subcommands
    if test (count $argv) -ge 1
        switch "$argv[1]"
            case update upgrade mcp config doctor install agents auto-mode auth plugin plugins --help -h --version -v
                command claude $argv
                return
        end
    end

    set -l claude_args $argv
    if set -q DEVCONTAINER
        set claude_args --dangerously-skip-permissions $argv
    end

    set -l short_cwd (string replace "$HOME" "~" "$PWD")

    if not set -q TMUX
        # Not in tmux — create a detached session, send claude into it, attach
        set -l sess_name "claude-$fish_pid"
        tmux new-session -d -s $sess_name -x (tput cols) -y (tput lines)
        tmux set-option -wt $sess_name automatic-rename off
        tmux rename-window -t $sess_name "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        set -l escaped_args (string join " " -- (string escape -- $claude_args))
        tmux send-keys -t $sess_name "command claude $escaped_args" Enter
        tmux attach-session -t $sess_name
    else
        # Already in tmux — rename current window and run directly
        tmux set-option -w automatic-rename off
        tmux rename-window "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        command claude $claude_args
    end
end
