function __ai_run --description 'Run the selected AI backend interactively'
    set -l backend $AI_BACKEND
    test -n "$backend"; or set backend claude
    switch $backend
        case claude
            claude $argv
        case pi
            env -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL command pi $argv
        case '*'
            echo "Unknown AI_BACKEND: $backend (expected claude or pi)" >&2
            return 2
    end
end
