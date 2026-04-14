function autoplan --description "Iterative TDD loop driven by a linked list of markdown plan files"
    argparse 'max-fix-attempts=' 'max-verify-passes=' 'no-pr' 'resume' -- $argv

    if test (count $argv) -eq 0
        echo "Usage: autoplan <plan-file> [--max-fix-attempts N] [--max-verify-passes N] [--no-pr] [--resume]" >&2
        return 1
    end

    set -l plan_file (realpath $argv[1])
    if not test -f $plan_file
        echo "Error: Plan file not found: $argv[1]" >&2
        return 1
    end

    set -l max_fix_attempts (set -q _flag_max_fix_attempts; and echo $_flag_max_fix_attempts; or echo 3)
    set -l max_verify_passes (set -q _flag_max_verify_passes; and echo $_flag_max_verify_passes; or echo 3)

    # Permission flag for devcontainer
    set -l perm_flag
    if set -q DEVCONTAINER
        set perm_flag --dangerously-skip-permissions
    end

    # ===== SETUP =====
    set -l branch (__autoplan_frontmatter $plan_file branch)
    set -l test_cmd (__autoplan_frontmatter $plan_file test_cmd)
    set -l pr_title (__autoplan_frontmatter $plan_file pr_title)
    set -l prompts_path (__autoplan_frontmatter $plan_file prompts)

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

    if not set -q _flag_resume
        if git show-ref --verify --quiet refs/heads/$branch
            echo "Branch $branch already exists. Use --resume to continue." >&2
            return 1
        end
        git fetch origin main
        git checkout --no-track -b $branch origin/main
    end

    mkdir -p ./tmp

    # ===== MAIN LOOP (linked list traversal) =====
    set -l current_plan $plan_file

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
        echo "🔍 Gate: Evaluating plan readiness..."

        set -l gate_output (command claude -p $perm_flag --model haiku --effort low \
            "Read plan at $current_plan. Evaluate: sufficient detail, clear scope, testable outcomes. If any part is too vague, output what's missing. If all automatable, output only \"READY\".")

        if not string match -q "*READY*" $gate_output
            echo "❌ Gate rejected. Feedback:" >&2
            echo "$gate_output" >&2
            return 1
        end
        echo "✅ Gate passed."

        # ===== IMPLEMENT =====
        echo ""
        echo "📝 Implement (TDD Red/Green)..."

        set -l impl_prompt (__autoplan_interpolate_prompt \
            (__autoplan_load_prompt "$prompts_path" implement) \
            $current_plan $branch)

        if test -z "$impl_prompt"
            set impl_prompt "Read the plan at $current_plan. Use /tdd skill -- write tests first (RED), then implement to pass (GREEN). Follow SOLID principles. Do NOT commit."
        end

        command claude -p $perm_flag --model sonnet --effort high "$impl_prompt"
        if test $status -ne 0
            echo "❌ Implement failed." >&2
            return 1
        end

        # ===== TEST/FIX LOOP =====
        set -l fix_attempt 0

        while true
            echo ""
            echo "🧪 Running tests..."

            if eval $test_cmd >./tmp/autoplan-test-output.txt 2>&1
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
                    $current_plan $branch)

                if test -z "$fix_prompt"
                    set fix_prompt "Tests are failing. Output at ./tmp/autoplan-test-output.txt.
Follow TDD: red → green → commit.
1. Read the test output to understand failures.
2. Fix the root cause. Do NOT weaken assertions. Do NOT skip or remove tests.
3. Re-run tests to confirm they pass.
4. Commit fixes."
                end

                claude $perm_flag --permission-mode plan "$fix_prompt"
            end
        end

        # ===== HARDEN =====
        echo ""
        echo "🔨 Harden..."

        set -l harden_prompt (__autoplan_interpolate_prompt \
            (__autoplan_load_prompt "$prompts_path" harden) \
            $current_plan $branch)

        if test -z "$harden_prompt"
            set harden_prompt "Review all uncommitted changes. Fix: duplication, SOLID violations, dead code, missing coverage. Re-run tests after each change. The plan at $current_plan provides context. Do NOT commit."
        end

        command claude -p $perm_flag --model sonnet --effort high "$harden_prompt"

        # ===== VERIFY/FIX LOOP =====
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
                $current_plan $branch)

            if test -z "$verify_prompt"
                set verify_prompt "Read the plan at $current_plan. Audit all changes on branch $branch. YOUR ROLE IS AUDIT-ONLY. Do NOT edit files, commit, push, or open a PR.
Check: (1) All scope items implemented, (2) Verification criteria from the plan are met, (3) No regressions, (4) Code quality (SOLID, no dead code).
If ALL checks pass: write ALL_GOOD to ./tmp/autoplan-verify-result.txt.
If ANY fail: write ISSUES_FOUND on line 1 of ./tmp/autoplan-verify-result.txt, numbered issues below."
            end

            command claude -p $perm_flag --model sonnet --effort medium "$verify_prompt"

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
                    $current_plan $branch)

                if test -z "$fix_verify_prompt"
                    set fix_verify_prompt "Verify step found issues. Read ./tmp/autoplan-verify-result.txt.
Follow TDD: red → green → commit.
1. Read each issue.
2. Fix the issues. Do NOT weaken, skip, or remove tests. Do NOT push or open a PR.
3. Re-run tests to confirm they pass.
4. Commit fixes."
                end

                claude $perm_flag --permission-mode plan "$fix_verify_prompt"

                # Reset fix attempts and go back through test/fix loop
                set fix_attempt 0
                while true
                    echo ""
                    echo "🧪 Re-running tests after verify fix..."

                    if eval $test_cmd >./tmp/autoplan-test-output.txt 2>&1
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
                            $current_plan $branch)

                        if test -z "$refix_prompt"
                            set refix_prompt "Tests are failing. Output at ./tmp/autoplan-test-output.txt.
Follow TDD: red → green → commit.
1. Read the test output to understand failures.
2. Fix the root cause. Do NOT weaken assertions. Do NOT skip or remove tests.
3. Re-run tests to confirm they pass.
4. Commit fixes."
                        end

                        claude $perm_flag --permission-mode plan "$refix_prompt"
                    end
                end
                # Continue verify loop
            else
                echo "❌ Verify did not write a recognized sentinel." >&2
                return 1
            end
        end

        # Save next and prompts_path BEFORE commit deletes the plan file
        set -l next_plan (__autoplan_frontmatter $current_plan next)

        # ===== COMMIT =====
        echo ""
        echo "💾 Commit..."

        command claude -p $perm_flag --model haiku --effort medium \
            "Run ALL tests/checks. Fix any failures. Commit all changes with a gitmoji message. Then delete the plan file $current_plan and commit that deletion."

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
        else
            break
        end
    end

    # ===== PR =====
    if not set -q _flag_no_pr
        echo ""
        echo "🚀 Creating PR..."

        set -l pr_body (command claude -p $perm_flag --model haiku --effort low \
            "Generate a concise PR summary from the git diff and log on branch $branch vs origin/main. Output markdown with ## Summary and ## Changes sections. No preamble.")

        git push origin $branch

        if gh pr view $branch >/dev/null 2>&1
            echo "PR already exists for $branch."
        else
            gh pr create --title "$pr_title" --body "$pr_body"
        end
    end

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
    # Args: prompt_text plan_file branch
    set -l prompt_text $argv[1]
    set -l plan_file $argv[2]
    set -l branch_name $argv[3]

    if test -z "$prompt_text"
        return
    end

    echo $prompt_text \
        | string replace -a '$PLAN_FILE' "$plan_file" \
        | string replace -a '$TEST_LOG' './tmp/autoplan-test-output.txt' \
        | string replace -a '$VERIFY_LOG' './tmp/autoplan-verify-result.txt' \
        | string replace -a '$BRANCH' "$branch_name"
end
