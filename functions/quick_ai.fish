function quick_ai --description 'Quick one-shot Claude (haiku) prompt'
    if test "$AI_BACKEND" = claude
        __ai_exec --model haiku -p (string join ' ' -- $argv)
    else
        __ai_exec -p (string join ' ' -- $argv)
    end
end
