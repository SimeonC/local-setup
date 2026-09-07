function p_ai --description 'Run the selected AI backend with /plan prefix'
    if test (count $argv) -gt 0
        __ai_run "/plan "(string join ' ' -- $argv)
    else
        __ai_run "/plan"
    end
end
