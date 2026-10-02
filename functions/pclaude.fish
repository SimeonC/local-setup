function pclaude --description 'Run Claude with /plan prefix'
    if test (count $argv) -gt 0
        claude "/plan "(string join ' ' -- $argv)
    else
        claude "/plan"
    end
end
