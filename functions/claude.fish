function claude --wraps=claude --description 'Coding agent with tmux session management (Claude or pi)'
    open "kaleidoscope://changeset?path=$PWD"

    # Set AI_BACKEND=pi to run every Claude-oriented helper through pi.
    # Keeping this dispatch here makes pclaude, autoplan, prclaude, etc. DRY.
    if test "$AI_BACKEND" = pi
        env -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL command pi $argv
        return $status
    end

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
        echo "__ai_exec" (string escape -- $claude_args) > $tmpscript
        # Pass command directly to new-session (not send-keys) so it's never typed
        # into an interactive shell and never recorded in history.
        # fish --private disables history for the session; tmux exits when claude exits.
        # tmux sessions inherit the SERVER's environment (captured from whichever
        # terminal first started tmux), not this shell's — so terminal-specific
        # identity vars (ORCA_*, CMUX_*, ...) leak into panes belonging to other
        # terminals. Make the session env match THIS shell: pass every var through
        # with -e, and clear vars that exist only in the server's env.
        set -l tmux_env_args
        set -l client_vars
        for kv in (env -0 | string split0)
            set -l name (string split -m 1 = $kv)[1]
            if string match -qr '^[A-Za-z_][A-Za-z0-9_]*$' -- $name
                set -a tmux_env_args -e $kv
                set -a client_vars $name
            end
        end
        for kv in (tmux show-environment -g 2>/dev/null | string match -r '^[A-Za-z_][A-Za-z0-9_]*=')
            set -l name (string split -m 1 = $kv)[1]
            if not contains -- $name $client_vars
                set -a tmux_env_args -e "$name="
            end
        end
        tmux new-session -d -s $sess_name $tmux_env_args -x (tput cols) -y (tput lines) \
            fish --private -c "source $tmpscript; rm $tmpscript"
        tmux set-option -wt $sess_name automatic-rename off
        tmux rename-window -t $sess_name "$short_cwd"
        tmux set-option -g set-titles on 2>/dev/null
        tmux set-option -g set-titles-string "tmux #W" 2>/dev/null
        # Stream raw pane output to captfile before attaching; used to recover the resume command
        tmux pipe-pane -t $sess_name "cat >> $captfile"
        tmux attach-session -t $sess_name
        # Re-print resume command extracted from raw captured output
        if test -f $captfile -a -s $captfile
            set -l resume_line (grep -aoE '(claude|pi) [^[:cntrl:]]+' $captfile 2>/dev/null | tail -1 | string trim)
            if test -n "$resume_line"
                echo ""
                echo "$resume_line"
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
        __ai_exec $claude_args
        for _entry in (builtin history search --prefix "command claude")
            builtin history delete --case-sensitive --exact -- $_entry
        end
    end
end
