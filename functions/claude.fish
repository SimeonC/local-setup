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
        # Write args to a temp script — avoids string escaping issues
        set -l tmpscript /tmp/.claude_(date +%Y%m%d_%H%M%S)_$fish_pid.fish
        echo "command claude" (string escape -- $claude_args) > $tmpscript
        # Pass command directly to new-session (not send-keys) so it's never typed
        # into an interactive shell and never recorded in history.
        # fish --private disables history for the session; exec fish hands back
        # a normal interactive shell after claude exits.
        tmux new-session -d -s $sess_name -x (tput cols) -y (tput lines) \
            fish --private -c "source $tmpscript; rm $tmpscript; exec fish"
        tmux set-option -wt $sess_name automatic-rename off
        tmux rename-window -t $sess_name "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        tmux attach-session -t $sess_name
        # Clean up any entries Claude Code wrote directly to the history file
        for _entry in (builtin history search --prefix "command claude")
            builtin history delete --case-sensitive --exact -- $_entry
        end
    else
        # Already in tmux — rename current window and run directly
        tmux set-option -w automatic-rename off
        tmux rename-window "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        command claude $claude_args
        for _entry in (builtin history search --prefix "command claude")
            builtin history delete --case-sensitive --exact -- $_entry
        end
    end
end
