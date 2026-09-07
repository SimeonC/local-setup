function pp_ai --description 'Plan-mode Claude with optional instruction prepended to clipboard content'
    set -l instruction (string join ' ' -- $argv)
    set -l pasted (pbpaste)
    if test -n "$instruction"
        __ai_run "/plan $instruction

$pasted"
    else
        __ai_run "/plan $pasted"
    end
end
