function autoplan-rewind --description "Interactively reset autoplan phase backward via fzf"
    set -l progress_file $PWD/.autoplan-progress
    if not test -f $progress_file
        echo "Error: No .autoplan-progress file found in current directory" >&2
        return 1
    end

    # Parse current state
    set -l current_plan ""
    set -l current_phase ""
    set -l pr_title ""

    for _line in (cat $progress_file)
        set -l _parts (string split -m 1 '=' $_line)
        switch $_parts[1]
            case plan;      set current_plan $_parts[2]
            case phase;     set current_phase $_parts[2]
            case pr_title;  set pr_title $_parts[2]
        end
    end

    if test -z "$current_plan" -o -z "$current_phase"
        echo "Error: Could not parse .autoplan-progress (plan or phase missing)" >&2
        return 1
    end

    # Phase order
    set -l all_phases prototype implement test_fix harden_verify verify_cmds commit chain_review_pr

    # Find current phase index
    set -l current_idx 0
    for i in (seq 1 (count $all_phases))
        if test "$all_phases[$i]" = "$current_phase"
            set current_idx $i
            break
        end
    end

    if test $current_idx -eq 0
        echo "Error: Current phase '$current_phase' not recognized" >&2
        return 1
    end

    # Offer phases before current (backward only)
    set -l earlier_phases $all_phases[1..(math $current_idx - 1)]
    if test (count $earlier_phases) -eq 0
        echo "Already at earliest phase (prototype) — cannot rewind further" >&2
        return 1
    end

    # Fzf picker for rewind target
    set -l chosen (printf '%s\n' $earlier_phases \
        | fzf --height=40% --reverse \
              --header="Rewind autoplan phase (current: $current_phase)" 2>/dev/null)
    if test $status -ne 0; or test -z "$chosen"
        return 1
    end

    # Update .autoplan-progress
    echo "plan=$current_plan" > $progress_file
    echo "phase=$chosen" >> $progress_file
    echo "pr_title=$pr_title" >> $progress_file

    echo "✅ Phase rewound: $current_phase → $chosen"
    echo "↩️  Resume with: autoplan"
end
