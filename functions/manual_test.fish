function manual_test --description "Autoplan: pause for human tester via editor; empty save = pass, content = failure"
    set -l instructions_file $argv[1]
    if test -z "$instructions_file" -o ! -f "$instructions_file"
        echo "manual_test: requires an existing instructions file path as the first arg." >&2
        return 1
    end
    mkdir -p ./tmp
    set -l file ./tmp/autoplan-manual-test.txt

    begin
        echo "# Manual test step — close the editor when done."
        echo "#"
        for line in (cat $instructions_file)
            echo "# $line"
        end
        echo "#"
        echo "# Describe any failures below. Lines starting with '#' are ignored."
        echo "# Save the file empty (or comments only) to mark the manual test as PASSED."
        echo ""
    end > $file

    # Claude Code injects GIT_EDITOR=true, which would silently auto-pass.
    # When CLAUDECODE is set, skip GIT_EDITOR and force a real editor.
    set -l editor
    if test "$CLAUDECODE" != 1
        set editor $GIT_EDITOR
    end
    test -z "$editor"; and set editor $VISUAL
    test -z "$editor"; and set editor $EDITOR
    test -z "$editor"; and set editor vi
    if not string match -q -- '*--wait*' $editor
        set editor "$editor --wait"
    end

    echo "🧑 Opening $editor for manual test report: $file"
    echo "   (Save AND close the file/tab to continue.)"
    eval $editor $file
    set -l ed_status $status
    if test $ed_status -ne 0
        echo "Editor exited non-zero ($ed_status); treating manual test as FAILED." >&2
        echo "MANUAL TEST FAILURE"
        echo ""
        echo "Editor aborted; no report captured."
        return 1
    end

    set -l details (grep -v '^#' $file | string trim | string collect)
    if test -z "$details"
        echo "✅ Manual test passed."
        return 0
    end
    echo "MANUAL TEST FAILURE"
    echo ""
    printf '%s\n' $details
    return 1
end
