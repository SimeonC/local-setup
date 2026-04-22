function print_claude --description 'Start a Claude Code session with --dangerously-skip-permissions and -p with nice output'
    claude --print --dangerously-skip-permissions --output-format stream-json --verbose $argv | format-claude-stream
end
