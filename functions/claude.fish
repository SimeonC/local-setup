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
        set -l captfile /tmp/.claude_resume_(date +%Y%m%d_%H%M%S)_$fish_pid.txt
        echo "command claude" (string escape -- $claude_args) > $tmpscript
        # Pass command directly to new-session (not send-keys) so it's never typed
        # into an interactive shell and never recorded in history.
        # fish --private disables history for the session; tmux exits when claude exits.
        tmux new-session -d -s $sess_name -x (tput cols) -y (tput lines) \
            fish --private -c "source $tmpscript; rm $tmpscript"
        tmux set-option -wt $sess_name automatic-rename off
        # remain-on-exit keeps the pane alive after the shell exits so the hook below can capture it
        tmux set-option -wt $sess_name remain-on-exit on
        tmux rename-window -t $sess_name "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        # pane-exited fires after shell exits while pane is still alive (remain-on-exit).
        # Capture pane content (contains resume block), then kill session so attach-session returns.
        tmux set-hook -t $sess_name pane-exited \
            "run-shell 'tmux capture-pane -p -S -200 -t $sess_name > $captfile 2>/dev/null; tmux kill-session -t $sess_name 2>/dev/null'"
        tmux attach-session -t $sess_name
        # Re-print claude's exit block (resume command etc.) which vanishes with the tmux pane
        if test -f $captfile -a -s $captfile
            set -l final_block (awk '
                /^[[:space:]]*$/ { buf = "" }
                !/^[[:space:]]*$/ { buf = (buf == "" ? $0 : buf "\n" $0) }
                END { printf "%s", buf }
            ' $captfile | string collect)
            if test -n "$final_block"
                if not string match -qr -- '--resume' "$final_block"
                    set -l resume_line (grep -o 'claude --resume [A-Za-z0-9_-]*' $captfile 2>/dev/null | tail -1)
                    if test -n "$resume_line"
                        echo ""
                        echo "$resume_line"
                    end
                else
                    echo ""
                    echo "$final_block"
                end
            end
            rm -f $captfile
        end
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
