function cat --wraps cat --description 'cat, but render .md files with mdcat'
    if not isatty stdout
        command cat $argv
        return
    end

    if test (count $argv) -eq 0
        command cat
        return
    end

    for arg in $argv
        if string match -q -- '-*' $arg
            command cat $argv
            return
        end
        if not string match -qi -- '*.md' $arg
            command cat $argv
            return
        end
    end

    if type -q mdcat
        mdcat $argv
    else
        command cat $argv
    end
end
