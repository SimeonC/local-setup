function pclaude --description 'Run Claude with /plan prefix'
    if test (count $argv) -gt 0
        danger_danger_claude "/plan "(string join ' ' -- $argv)
    else
        danger_danger_claude "/plan"
    end
end
