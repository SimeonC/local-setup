function smart_prettier
    set modified_files (git diff --name-only --diff-filter=ACMTRUX HEAD 2>/dev/null)
    if test $status -ne 0
        set modified_files
    end

    set formatter ""
    set formatter_args

    if test -f package.json
        if grep -q '"prettier"' package.json
            set formatter prettier
            set formatter_args --log-level error --write
        else if grep -q '"oxfmt"' package.json
            set formatter oxfmt
            set formatter_args --write
        end
    end

    if test -z "$formatter"
        echo (set_color red)"No formatter found in package.json (prettier or oxfmt)"(set_color normal)
        return 1
    end

    echo (set_color cyan)"Using formatter: $formatter"(set_color normal)
    if test "$formatter" = prettier
        echo "Prettier Version: " (_pm_exec prettier --version)
    end

    if test "$argv" = --force; or test "$argv" = -f
        echo (set_color yellow)"Force formatting all files"(set_color normal)
        _pm_exec $formatter $formatter_args .
    else if test (count $modified_files) -eq 0
        echo (set_color green)"No changes or not a git repository, formatting all files"(set_color normal)
        _pm_exec $formatter $formatter_args .
    else
        echo (set_color yellow)"Formatting "(count $modified_files)" changed files"(set_color normal)
        _pm_exec $formatter $formatter_args $modified_files
    end
end
