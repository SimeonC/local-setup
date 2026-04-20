function autoplan --description "Iterative TDD loop driven by a linked list of markdown plan files"
    argparse 'max-fix-attempts=' 'max-verify-passes=' 'no-pr' 'resume' 'continue' -- $argv

    if set -q _flag_continue
        if not test -f .autoplan-progress
            echo "Error: No .autoplan-progress file found. Cannot --continue without it." >&2
            return 1
        end
    else if test (count $argv) -eq 0
        echo "Usage: autoplan <plan-file> [--max-fix-attempts N] [--max-verify-passes N] [--no-pr] [--resume] [--continue]" >&2
        return 1
    end

    set -l max_fix_attempts (set -q _flag_max_fix_attempts; and echo $_flag_max_fix_attempts; or echo 3)
    set -l max_verify_passes (set -q _flag_max_verify_passes; and echo $_flag_max_verify_passes; or echo 3)

    # Permission mode
    set -l permission_mode acceptEdits
    if set -q DEVCONTAINER
        set permission_mode bypassPermissions
    else
        read -P "Allow Claude to skip permissions (dangerous mode)? [y/N] " -l _dangerous_mode
        if string match -qi 'y*' $_dangerous_mode
            set permission_mode bypassPermissions
        end
    end

    # ===== SETUP =====
    set -l plan_file ""
    set -l branch ""
    set -l current_plan ""
    # Clear any stale global skip_to_phase from a previous run in this session
    set -eg skip_to_phase

    if set -q _flag_continue
        # Load state from .autoplan-progress
        for _line in (cat .autoplan-progress)
            set -l _parts (string split -m 1 '=' $_line)
            switch $_parts[1]
                case root_plan; set plan_file $_parts[2]
                case plan;      set current_plan $_parts[2]
                case phase;     set -g skip_to_phase $_parts[2]
                case branch;    set branch $_parts[2]
            end
        end
        if not git show-ref --verify --quiet refs/heads/$branch
            echo "Error: Branch $branch not found in local refs." >&2
            return 1
        end
        if test (git branch --show-current) != $branch
            git checkout $branch
        end
    else
        set plan_file (realpath $argv[1])
        if not test -f $plan_file
            echo "Error: Plan file not found: $argv[1]" >&2
            return 1
        end
        set current_plan $plan_file
    end

    set -l test_cmd (__autoplan_frontmatter $plan_file test_cmd)
    set -l pr_title (__autoplan_frontmatter $plan_file pr_title)
    set -l prompts_path (__autoplan_frontmatter $plan_file prompts)

    if test -z "$branch"
        set branch (__autoplan_frontmatter $plan_file branch)
    end

    if test -z "$branch"
        echo "Error: Plan file missing required frontmatter key: branch" >&2
        return 1
    end
    if test -z "$test_cmd"
        echo "Error: Plan file missing required frontmatter key: test_cmd" >&2
        return 1
    end
    if test -z "$pr_title"
        echo "Error: Plan file missing required frontmatter key: pr_title" >&2
        return 1
    end

    # Resolve prompts path relative to plan file directory
    if test -n "$prompts_path" -a ! -f "$prompts_path"
        set -l plan_dir (dirname $plan_file)
        set prompts_path "$plan_dir/$prompts_path"
    end

    if not set -q _flag_resume; and not set -q _flag_continue
        if git show-ref --verify --quiet refs/heads/$branch
            echo "Branch $branch already exists. Use --resume to continue." >&2
            return 1
        end
        if not git diff --quiet HEAD
            echo "Error: Uncommitted changes in working tree. Commit or stash before running autoplan." >&2
            return 1
        end
        git fetch origin main
        git checkout --no-track -b $branch origin/main
    end

    mkdir -p ./tmp

    set -l base_system_prompt "## Autoplan Global Rules
- Write any temporary context or source-dump files to ./tmp/ with an autoplan- prefix (e.g. ./tmp/autoplan-context.txt). Never write to /tmp/ (global) or the project root.
- Do NOT commit — the pipeline handles commits separately.
- Do NOT push to remote or open a PR — the pipeline handles that.
- Do NOT weaken, skip, disable, or remove tests to fix failures — fix the implementation instead.
- Follow SOLID principles.
- Follow existing codebase patterns and conventions — match naming, file structure, and idioms already in use."

    # ===== MAIN LOOP (linked list traversal) =====
    while true
        # Re-load per-plan overrides (test_cmd, prompts can be overridden)
        set -l plan_test_cmd (__autoplan_frontmatter $current_plan test_cmd)
        if test -n "$plan_test_cmd"
            set test_cmd $plan_test_cmd
        end
        set -l plan_prompts (__autoplan_frontmatter $current_plan prompts)
        if test -n "$plan_prompts"
            set prompts_path $plan_prompts
            if test ! -f "$prompts_path"
                set -l plan_dir (dirname $current_plan)
                set prompts_path "$plan_dir/$prompts_path"
            end
        end

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Plan: $current_plan"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # ===== GATE =====
        if not __autoplan_check_skip gate
            __autoplan_save_state $plan_file $current_plan gate $branch
            echo "🔍 Gate: Evaluating and fixing plan if needed..."

            rm -f ./tmp/autoplan-gate-output.txt
            set -l gate_prompt_file "$HOME/.claude/skills/autoplan/references/gate-prompt.md"
            set -l gate_prompt (cat $gate_prompt_file \
                | string replace -a -- '$PLAN_FILE' "$current_plan" \
                | string replace -a -- '$GATE_LOG' './tmp/autoplan-gate-output.txt')
            command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort medium "$gate_prompt"
            set -l gate_output (cat ./tmp/autoplan-gate-output.txt 2>/dev/null)

            if string match -q -- "*CANNOT_FIX*" $gate_output
                echo "❌ Gate: plan cannot be made automatable:" >&2
                echo "$gate_output" >&2
                return 1
            else if not string match -q -- "*READY*" $gate_output
                echo "❌ Gate: sentinel file missing or unrecognised." >&2
                return 1
            end
            echo "✅ Gate passed."
        end

        # ===== IMPLEMENT =====
        if not __autoplan_check_skip implement
            __autoplan_save_state $plan_file $current_plan implement $branch
            echo ""
            echo "📝 Implement (TDD Red/Green)..."

            set -l impl_prompt (__autoplan_interpolate_prompt \
                (__autoplan_load_prompt "$prompts_path" implement) \
                $current_plan $branch $test_cmd)

            if test -z "$impl_prompt"
                set impl_prompt (__autoplan_interpolate_prompt \
                    (cat "$HOME/.claude/skills/autoplan/references/implement-prompt.md") \
                    $current_plan $branch $test_cmd)
            end

            command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort high "$impl_prompt"
            if test $status -ne 0
                echo "❌ Implement failed." >&2
                return 1
            end
        end

        # ===== TEST/FIX LOOP =====
        if not __autoplan_check_skip test_fix
            __autoplan_save_state $plan_file $current_plan test_fix $branch
            set -l fix_attempt 0

            while true
                echo ""
                echo "🧪 Running tests..."

                if __autoplan_run_tests "$test_cmd" ./tmp/autoplan-test-output.txt
                    echo "✅ Tests pass."
                    break
                else
                    set fix_attempt (math $fix_attempt + 1)
                    if test $fix_attempt -ge $max_fix_attempts
                        echo "❌ Tests still failing after $max_fix_attempts fix attempts." >&2
                        echo "Test output: ./tmp/autoplan-test-output.txt" >&2
                        return 1
                    end

                    echo "⚠️  Tests failing (attempt $fix_attempt/$max_fix_attempts). Fixing..."

                    set -l fix_prompt (__autoplan_interpolate_prompt \
                        (__autoplan_load_prompt "$prompts_path" fix_test) \
                        $current_plan $branch $test_cmd)

                    if test -z "$fix_prompt"
                        set fix_prompt (__autoplan_interpolate_prompt \
                            (cat "$HOME/.claude/skills/autoplan/references/fix-test-prompt.md") \
                            $current_plan $branch $test_cmd)
                    end

                    claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" "/plan $fix_prompt"
                end
            end
        end

        # ===== HARDEN =====
        if not __autoplan_check_skip harden
            __autoplan_save_state $plan_file $current_plan harden $branch
            echo ""
            echo "🔨 Harden..."

            set -l harden_prompt (__autoplan_interpolate_prompt \
                (__autoplan_load_prompt "$prompts_path" harden) \
                $current_plan $branch $test_cmd)

            if test -z "$harden_prompt"
                set harden_prompt (__autoplan_interpolate_prompt \
                    (cat "$HOME/.claude/skills/autoplan/references/harden-prompt.md") \
                    $current_plan $branch $test_cmd)
            end

            command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort high "$harden_prompt"
        end

        # ===== VERIFY/FIX LOOP =====
        if not __autoplan_check_skip verify_fix
            __autoplan_save_state $plan_file $current_plan verify_fix $branch
            set -l verify_pass 0

            while true
                set verify_pass (math $verify_pass + 1)
                if test $verify_pass -gt $max_verify_passes
                    echo "❌ Verify still finding issues after $max_verify_passes passes." >&2
                    return 1
                end

                echo ""
                echo "🔎 Verify (pass $verify_pass/$max_verify_passes)..."

                rm -f ./tmp/autoplan-verify-result.txt

                set -l verify_prompt (__autoplan_interpolate_prompt \
                    (__autoplan_load_prompt "$prompts_path" verify) \
                    $current_plan $branch $test_cmd)

                if test -z "$verify_prompt"
                    set verify_prompt (__autoplan_interpolate_prompt \
                        (cat "$HOME/.claude/skills/autoplan/references/verify-prompt.md") \
                        $current_plan $branch $test_cmd)
                end

                command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort medium "$verify_prompt"

                if not test -f ./tmp/autoplan-verify-result.txt
                    echo "❌ Verify did not write sentinel file." >&2
                    return 1
                end

                if head -1 ./tmp/autoplan-verify-result.txt | string match -qr '^ALL_GOOD'
                    echo "✅ Verify passed."
                    break
                else if head -1 ./tmp/autoplan-verify-result.txt | string match -qr '^ISSUES_FOUND'
                    echo "⚠️  Verify found issues. Fixing..."

                    set -l fix_verify_prompt (__autoplan_interpolate_prompt \
                        (__autoplan_load_prompt "$prompts_path" fix_verify) \
                        $current_plan $branch $test_cmd)

                    if test -z "$fix_verify_prompt"
                        set fix_verify_prompt (__autoplan_interpolate_prompt \
                            (cat "$HOME/.claude/skills/autoplan/references/fix-verify-prompt.md") \
                            $current_plan $branch $test_cmd)
                    end

                    claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" "/plan $fix_verify_prompt"

                    # Reset fix attempts and go back through test/fix loop
                    set fix_attempt 0
                    while true
                        echo ""
                        echo "🧪 Re-running tests after verify fix..."

                        if __autoplan_run_tests "$test_cmd" ./tmp/autoplan-test-output.txt
                            echo "✅ Tests pass."
                            break
                        else
                            set fix_attempt (math $fix_attempt + 1)
                            if test $fix_attempt -ge $max_fix_attempts
                                echo "❌ Tests still failing after $max_fix_attempts fix attempts." >&2
                                return 1
                            end

                            echo "⚠️  Tests failing (attempt $fix_attempt/$max_fix_attempts). Fixing..."

                            set -l refix_prompt (__autoplan_interpolate_prompt \
                                (__autoplan_load_prompt "$prompts_path" fix_test) \
                                $current_plan $branch $test_cmd)

                            if test -z "$refix_prompt"
                                set refix_prompt (__autoplan_interpolate_prompt \
                                    (cat "$HOME/.claude/skills/autoplan/references/fix-test-prompt.md") \
                                    $current_plan $branch $test_cmd)
                            end

                            claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" "/plan $refix_prompt"
                        end
                    end
                    # Continue verify loop
                else
                    echo "❌ Verify did not write a recognized sentinel." >&2
                    return 1
                end
            end
        end

        # Save next plan path BEFORE commit (commit may delete the plan file)
        set -l next_plan (__autoplan_frontmatter $current_plan next)

        # ===== COMMIT =====
        if not __autoplan_check_skip commit
            __autoplan_save_state $plan_file $current_plan commit $branch
            echo ""
            echo "💾 Commit..."

            set -l commit_prompt (__autoplan_interpolate_prompt \
                (cat "$HOME/.claude/skills/autoplan/references/commit-prompt.md") \
                $current_plan $branch $test_cmd)
            set commit_prompt (string replace -a -- '$PROMPTS_FILE' "$prompts_path" $commit_prompt)
            command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model haiku --effort medium "$commit_prompt"
        end

        # Follow linked list
        if test -n "$next_plan"
            # Resolve next path relative to the completed plan's directory
            if test ! -f "$next_plan"
                set -l plan_dir (dirname $current_plan)
                set next_plan "$plan_dir/$next_plan"
            end
            set next_plan (realpath $next_plan)
            if not test -f $next_plan
                echo "❌ Next plan not found: $next_plan" >&2
                return 1
            end
            set current_plan $next_plan
            # Update state so --continue resumes at the next plan's gate
            __autoplan_save_state $plan_file $current_plan gate $branch
        else
            break
        end
    end

    # ===== CHAIN REVIEW =====
    __autoplan_save_state $plan_file $current_plan chain_review $branch
    if not __autoplan_check_skip chain_review
        echo ""
        echo "🔍 Chain review..."

        set -l plan_dir (dirname $plan_file)
        set -l review_prompt "Review the completed autoplan chain and clean up.

## Step 1: Review commits
Run: git log --oneline origin/main..$branch
Check each commit against the original plan scope to verify nothing was missed or left incomplete.

## Step 2: Clean up leftover files
Delete any remaining autoplan plan/prompts .md files in $plan_dir that were part of this chain.
Do NOT delete files that aren't part of this autoplan chain.
If there are files to delete, stage and commit:
  🔥 Remove completed plan files

## Step 3: Summary
Output a brief summary of what was completed and flag anything that looks incomplete."

        command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model opus "$review_prompt"
    end

    # ===== PR =====
    if not set -q _flag_no_pr
        __autoplan_save_state $plan_file $current_plan pr $branch
        if not __autoplan_check_skip pr
            echo ""
            echo "🚀 Creating PR..."

            rm -f ./tmp/autoplan-pr-body.txt
            set -l pr_prompt (__autoplan_interpolate_prompt \
                (cat "$HOME/.claude/skills/autoplan/references/pr-body-prompt.md") \
                $current_plan $branch $test_cmd)
            command claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model haiku --effort low "$pr_prompt"
            set -l pr_body (cat ./tmp/autoplan-pr-body.txt 2>/dev/null)

            git push origin $branch

            if gh pr view $branch >/dev/null 2>&1
                echo "PR already exists for $branch."
            else
                gh pr create --title "$pr_title" --body "$pr_body"
            end
        end
    end

    # ===== CLEANUP =====
    rm -f ./tmp/autoplan-*
    rm -f .autoplan-progress

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Autoplan complete."
    return 0
end

# --- Helper functions ---

function __autoplan_frontmatter --argument-names plan_file key --description "Extract a frontmatter value from a plan file"
    sed -n '/^---$/,/^---$/p' $plan_file | grep "^$key:" | sed "s/^$key: *//" | tr -d '"' | string trim
end

function __autoplan_load_prompt --argument-names prompts_file stage --description "Load a prompt section from a prompts file"
    if test -z "$prompts_file" -o ! -f "$prompts_file"
        return
    end
    # Extract from ## stage to next ## header (inclusive), drop header lines
    sed -n "/^## $stage\$/,/^## /p" $prompts_file | sed '1d' | grep -v '^## '
end

function __autoplan_interpolate_prompt --description "Interpolate variables in a prompt string"
    # Calling convention: all args except last three are prompt lines; last three are plan_file, branch, test_cmd.
    # __autoplan_load_prompt output is split into a fish list by command substitution, so we must
    # join everything before plan_file/branch/test_cmd rather than assuming a fixed argv[1].
    set -l test_cmd_val $argv[-1]
    set -l branch_name $argv[-2]
    set -l plan_file $argv[-3]
    set -l prompt_lines $argv[1..-4]

    if test (count $prompt_lines) -eq 0
        return
    end

    printf '%s\n' $prompt_lines \
        | string replace -a -- '$PLAN_FILE' "$plan_file" \
        | string replace -a -- '$TEST_LOG' './tmp/autoplan-test-output.txt' \
        | string replace -a -- '$VERIFY_LOG' './tmp/autoplan-verify-result.txt' \
        | string replace -a -- '$BRANCH' "$branch_name" \
        | string replace -a -- '$TEST_CMD' "$test_cmd_val" \
        | string replace -a -- '$GATE_LOG' './tmp/autoplan-gate-output.txt'
end

function __autoplan_run_tests --argument-names test_cmd output_file --description "Run test command(s), splitting on && for progress output"
    echo -n >$output_file
    for cmd in (string split '&&' -- $test_cmd)
        set cmd (string trim $cmd)
        test -z "$cmd"; and continue
        echo "▶ $cmd"
        CI=true eval $cmd 2>&1 | tee -a $output_file
        if test $pipestatus[1] -ne 0
            return 1
        end
    end
    return 0
end

function __autoplan_save_state --argument-names root_plan plan phase branch
    echo "root_plan=$root_plan" > .autoplan-progress
    echo "plan=$plan" >> .autoplan-progress
    echo "phase=$phase" >> .autoplan-progress
    echo "branch=$branch" >> .autoplan-progress
end

function __autoplan_phase_index --argument-names phase
    switch $phase
        case gate;         echo 1
        case implement;    echo 2
        case test_fix;     echo 3
        case harden;       echo 4
        case verify_fix;   echo 5
        case commit;       echo 6
        case chain_review; echo 7
        case pr;           echo 8
        case '*';          echo 0
    end
end

function __autoplan_check_skip --argument-names phase
    # Returns 0 (true = skip) if this phase should be skipped
    # Returns 1 (false = run) if this phase should execute
    # Side effect: clears global skip_to_phase when the target phase is reached
    if not set -q skip_to_phase
        return 1  # No skip target; run the phase
    end
    if test (__autoplan_phase_index $phase) -lt (__autoplan_phase_index $skip_to_phase)
        echo "⏭  Skipping $phase (resuming at $skip_to_phase)..."
        return 0  # Skip this phase
    end
    # Reached or passed target — clear skip and run
    set -eg skip_to_phase
    return 1  # Run this phase
end
