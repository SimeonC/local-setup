function quick_claude --description 'Quick one-shot Claude (haiku) prompt'
    claude --model haiku -p (string join ' ' -- $argv)
end
