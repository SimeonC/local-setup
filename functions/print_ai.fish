function print_ai --description 'Start a Claude Code session with --dangerously-skip-permissions and -p with nice output'
    __ai_exec --print --dangerously-skip-permissions --output-format stream-json --verbose $argv | format-claude-stream
end
