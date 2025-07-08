function system_setup
    set -l lines (asdf current 2>&1)

    for line in $lines
        set matches (string match -r "Not installed\. Run \"([^\"]+)\"" $line)
        if test -n "$matches"
            set -l install_command $matches[2]
            echo "Running $install_command"
            eval $install_command
        end
    end
end
