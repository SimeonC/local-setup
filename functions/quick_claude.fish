function quick_claude --description 'Quick one-shot Claude (haiku) prompt'
    danger_danger_claude --model haiku -p (string join ' ' -- $argv)
end
