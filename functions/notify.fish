function notify
    set -l title $argv[2]
    if test -z "$title"
        if set -q CMUX_WORKSPACE_ID
            set -l panel_line (cmux list-panels --workspace $CMUX_WORKSPACE_ID | string match -r '^\*.*\[focused\].*')
            set -l workspace_line (cmux workspace list | string match -r '^\*.*\[selected\].*')

            set -l m
            set -l n
            if test -n "$panel_line"
                set m (string match -r '"([^"]+)"' -- $panel_line)
            end
            if test -n "$workspace_line"
                set n (string match -r '^\*\s+workspace:\d+\s+(.+?)\s+\[selected\]' -- $workspace_line)
            end

            if test -n "$m[2]"; and test -n "$n[2]"
                set title "$n[2] / $m[2]"
            else if test -n "$m[2]"
                set title $m[2]
            else if test -n "$n[2]"
                set title $n[2]
            end
        end
        if test -z "$title"
            if set -q TMUX
                set title (tmux display-message -p '#S / #W')
            else
                set title (basename $PWD)
            end
        end
    end
    osascript -e "display notification \"$argv[1]\" with title \"$title\""
end
