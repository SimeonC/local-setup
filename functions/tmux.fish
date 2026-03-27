function tmux --wraps=tmux --description 'tmux with per-surface server when in cmux'
    if set -q CMUX_SURFACE_ID
        command tmux -L cmux-$CMUX_SURFACE_ID $argv
    else
        command tmux $argv
    end
end
