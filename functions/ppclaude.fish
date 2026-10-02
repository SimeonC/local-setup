function ppclaude --description 'Plan-mode Claude with optional instruction prepended to clipboard content'
    set -l instruction (string join ' ' -- $argv)
    set -l pasted (pbpaste)
    if test -n "$instruction"
        claude "/plan $instruction

$pasted"
    else
        claude "/plan $pasted"
    end
end
