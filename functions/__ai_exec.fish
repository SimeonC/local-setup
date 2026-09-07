function __ai_exec --description 'Execute the selected AI backend with Claude-compatible arguments'
    set -l backend $AI_BACKEND
    if test -z "$backend"
        set backend claude
    end

    if test "$backend" = claude
        command claude $argv
        return $status
    end
    if test "$backend" != pi
        echo "Unknown AI_BACKEND: $backend (expected claude or pi)" >&2
        return 2
    end

    # Keep the shared helpers Claude-shaped, translating only flags that pi does
    # not have. pi's normal JSON mode is the closest equivalent to stream-json.
    set -l pi_args
    set -l skip 0
    for arg in $argv
        if test $skip -eq 1
            set skip 0
            continue
        end
        switch $arg
            case --dangerously-skip-permissions --verbose
                continue
            case --output-format
                set skip 1
                set -a pi_args --mode json
            case --permission-mode --agent --effort
                set skip 1
            case --print
                set -a pi_args --print
            case '*'
                set -a pi_args $arg
        end
    end

    env -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL command pi $pi_args
end
