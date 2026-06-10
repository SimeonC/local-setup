function autoplan --description "Iterative TDD loop driven by a linked list of markdown plan files"
    # Re-launch inside tmux if not already running in a tmux session.
    #
    # The pane runs as a non-interactive `fish -c`, which has job control OFF, so
    # every child (verify/test commands — e.g. playwright's server, which you stop
    # with Ctrl-C) shares autoplan's process group. A bare Ctrl-C would deliver
    # SIGINT to the whole group, killing autoplan along with the child — and since
    # autoplan is the pane's only process, that ends the tmux session and closes
    # the cmux tab. Guard against it: ignore SIGINT at the autoplan-shell level and
    # turn job control on, so Ctrl-C kills only the current child and the whole
    # autoplan loop survives. The guard lives only in this ephemeral pane shell, so
    # it never leaks into an interactive session. (The already-in-tmux path below
    # is interactive and so already job-controlled — no guard needed there.)
    if not set -q TMUX
        set -l escaped_args (string escape -- $argv)
        exec tmux new-session fish -c "function __autoplan_sigint_guard --on-signal INT; end; status job-control full; autoplan $escaped_args"
    end

    argparse 'max-fix-attempts=' 'max-verify-passes=' 'continue' -- $argv

    # Run-root anchoring: all state/tmp paths are relative to where autoplan is launched
    set -g __autoplan_root $PWD

    if set -q _flag_continue
        if not test -f $__autoplan_root/.autoplan-progress
            echo "Error: No .autoplan-progress file found. Cannot --continue without it." >&2
            return 1
        end
    else if test (count $argv) -eq 0
        echo "Usage: autoplan <plan-file> [--max-fix-attempts N] [--max-verify-passes N] [--continue]" >&2
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
    set -l current_plan ""
    set -l pr_title ""
    # Clear any stale global skip_to_phase from a previous run in this session
    set -eg skip_to_phase

    if set -q _flag_continue
        # Load state from .autoplan-progress
        for _line in (cat $__autoplan_root/.autoplan-progress)
            set -l _parts (string split -m 1 '=' $_line)
            switch $_parts[1]
                case plan;      set current_plan $_parts[2]
                case phase;     set -g skip_to_phase $_parts[2]
                case pr_title;  set pr_title $_parts[2]
            end
        end
    else
        set current_plan (realpath $argv[1])
        if not test -f $current_plan
            echo "Error: Plan file not found: $argv[1]" >&2
            return 1
        end
    end

    set -l test_cmd (__autoplan_frontmatter $current_plan test_cmd)
    if test -z "$pr_title"
        set pr_title (__autoplan_frontmatter $current_plan pr_title)
    end
    set -l prompts_path (__autoplan_frontmatter $current_plan prompts)
    set -l env_files (__autoplan_frontmatter_list $current_plan env_files)
    set -l manual_test_file (__autoplan_frontmatter $current_plan manual_test)
    if test -n "$manual_test_file"
        if not string match -q '/*' $manual_test_file
            set manual_test_file (dirname $current_plan)/$manual_test_file
        end
        if not test -f "$manual_test_file"
            echo "Error: manual_test file not found: $manual_test_file" >&2
            return 1
        end
    end

    if test -z "$test_cmd" -a -z "$manual_test_file"
        echo "Error: Plan file must have test_cmd, manual_test, or both." >&2
        return 1
    end
    if test (count $env_files) -gt 0; and not type -q dotenvx
        echo "Error: Plan uses env_files but dotenvx is not installed. Install with: brew install dotenvx/brew/dotenvx" >&2
        return 1
    end
    if test -n "$prompts_path"
        if not string match -q '/*' $prompts_path
            set prompts_path (dirname $current_plan)/$prompts_path
        end
        if not test -f "$prompts_path"
            echo "Error: prompts file not found: $prompts_path" >&2
            return 1
        end
    end

    mkdir -p $__autoplan_root/tmp

    set -l base_system_prompt (__autoplan_compose_system base)
    set -l implement_system_prompt     (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm implement)
    set -l fix_test_system_prompt      (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-test)
    set -l fix_verify_system_prompt    (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-verify)
    set -l fix_verify_cmd_system_prompt (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-verify-cmd)
    set -l harden_system_prompt        (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm harden)
    set -l verify_system_prompt        (__autoplan_compose_system base stage-restrictions scope verify)

    # ===== MAIN LOOP (linked list traversal) =====
    while true
        # Re-load per-plan overrides (test_cmd, prompts can be overridden)
        set -l plan_test_cmd (__autoplan_frontmatter $current_plan test_cmd)
        if test -n "$plan_test_cmd"
            set test_cmd $plan_test_cmd
        end
        set -l plan_prompts (__autoplan_frontmatter $current_plan prompts)
        if test -n "$plan_prompts"
            if not string match -q '/*' $plan_prompts
                set prompts_path (dirname $current_plan)/$plan_prompts
            else
                set prompts_path $plan_prompts
            end
        end
        set -l plan_env_files (__autoplan_frontmatter_list $current_plan env_files)
        if test (count $plan_env_files) -gt 0
            set env_files $plan_env_files
            if not type -q dotenvx
                echo "Error: Plan uses env_files but dotenvx is not installed. Install with: brew install dotenvx/brew/dotenvx" >&2
                return 1
            end
        end
        set -l plan_manual_test (__autoplan_frontmatter $current_plan manual_test)
        if test -n "$plan_manual_test"
            if not string match -q '/*' $plan_manual_test
                set manual_test_file (dirname $current_plan)/$plan_manual_test
            else
                set manual_test_file $plan_manual_test
            end
        end

        # ===== PER-PLAN CWD + BRANCH =====

        # Resolve cwd: relative paths are anchored to the run root
        set -l plan_cwd_raw (__autoplan_frontmatter $current_plan cwd)
        if test -z "$plan_cwd_raw"
            set plan_cwd_raw .
        end
        set -l plan_cwd
        if string match -q '/*' $plan_cwd_raw
            set plan_cwd $plan_cwd_raw
        else
            set plan_cwd $__autoplan_root/$plan_cwd_raw
        end
        set plan_cwd (realpath $plan_cwd 2>/dev/null)
        if not test -d "$plan_cwd"
            echo "Error: cwd '$plan_cwd_raw' not found for plan $current_plan" >&2
            return 1
        end
        __autoplan_activate_tools $plan_cwd

        # Re-read branch per plan
        set -l branch (__autoplan_frontmatter $current_plan branch)

        if test -z "$branch"; or test "$branch" = "<current>"
            # Adopt-current mode: use whatever branch the repo is on
            set -l current_branch (git -C $plan_cwd branch --show-current 2>/dev/null)
            if test -z "$current_branch"
                echo "Error: Repo at '$plan_cwd' is in detached HEAD state. Checkout a branch first." >&2
                return 1
            end

            # Chooser: show fzf for every adopt-current plan (skip on resume)
            if test -t 0; and not set -q DEVCONTAINER
                and not set -q skip_to_phase
                and type -q fzf
                set -l out (git -C $plan_cwd branch --format='%(refname:short)' \
                    | fzf --print-query --query="$current_branch" --height=40% --reverse \
                          --header="Branch for $plan_cwd — Enter to pick · type new name + Enter to create" 2>/dev/null)
                set -l fzf_status $status
                switch $fzf_status
                    case 0
                        # Existing branch selected (last line = selection)
                        set current_branch $out[-1]
                        if test (git -C $plan_cwd branch --show-current) != $current_branch
                            git -C $plan_cwd checkout $current_branch
                        end
                    case 1
                        # No match — typed query becomes new branch off HEAD
                        if test -z "$out[1]"
                            echo "Error: No branch name typed." >&2
                            return 1
                        end
                        set current_branch $out[1]
                        git -C $plan_cwd checkout -b $current_branch
                    case '*'
                        # 130 = Esc / abort
                        return 1
                end
            else if test -t 0; and not set -q DEVCONTAINER
                and not set -q skip_to_phase
                and not type -q fzf
                echo "note: fzf not installed — adopting current branch '$current_branch' in $plan_cwd (install with: brew install fzf)"
            end

            set branch $current_branch
        else
            # Ensure-branch mode: branch: <name> is specified
            if git -C $plan_cwd show-ref --verify --quiet refs/heads/$branch
                # Branch exists locally — checkout if not current
                if test (git -C $plan_cwd branch --show-current) != $branch
                    git -C $plan_cwd checkout $branch
                end
            else if not set -q skip_to_phase
                # New branch: guard dirty tree, then create from origin/main
                if not git -C $plan_cwd diff --quiet HEAD
                    echo "Error: Uncommitted changes in working tree. Commit or stash before running autoplan." >&2
                    return 1
                end
                git -C $plan_cwd fetch origin main
                git -C $plan_cwd checkout --no-track -b $branch origin/main
            else
                echo "Error: Branch '$branch' not found locally (expected when resuming)." >&2
                return 1
            end

            # Assert we are on the correct branch before proceeding
            if test (git -C $plan_cwd branch --show-current) != $branch
                echo "Error: Repo is on branch '$(git -C $plan_cwd branch --show-current)' but plan requires '$branch'. Switch manually." >&2
                return 1
            end
        end

        set -l plan_desc (__autoplan_frontmatter $current_plan description)
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Plan: $current_plan"
        if test -n "$plan_desc"
            echo "$plan_desc"
        end
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # ===== IMPLEMENT =====
        if not __autoplan_check_skip implement
            __autoplan_save_state $current_plan implement $pr_title
            echo "🛠️  Implement..."

            set -l impl_sub (__autoplan_build_user_prompt \
                implement-prompt.md DOMAIN_IMPLEMENT implement \
                "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

            env -C $plan_cwd claude --permission-mode $permission_mode \
                --append-system-prompt "$implement_system_prompt" "$impl_sub"

            echo "✅ Implement complete."
        end

        # ===== TEST/FIX LOOP =====
        if not __autoplan_check_skip test_fix
            __autoplan_save_state $current_plan test_fix $pr_title
            set -l fix_attempt 0

            while true
                echo ""
                echo "🧪 Running tests..."

                if __autoplan_run_tests $plan_cwd "$test_cmd" $__autoplan_root/tmp/autoplan-test-output.txt "$manual_test_file" $env_files
                    echo "✅ Tests pass."
                    break
                else
                    set fix_attempt (math $fix_attempt + 1)
                    if test $fix_attempt -ge $max_fix_attempts
                        echo "⚠️  Tests still failing after $max_fix_attempts fix attempts." >&2
                        echo "Test output: $__autoplan_root/tmp/autoplan-test-output.txt" >&2
                        read -P "Continue cycling fix attempts? [y/N] " -l _continue_fix
                        if string match -qi 'y*' $_continue_fix
                            set fix_attempt 0
                        else
                            return 1
                        end
                    end

                    echo "⚠️  Tests failing (attempt $fix_attempt/$max_fix_attempts). Fixing..."

                    set -l fix_prompt (__autoplan_build_user_prompt \
                        fix-test-prompt.md DOMAIN_FIX_TEST fix_test \
                        "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                    env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$fix_test_system_prompt" "/plan $fix_prompt"
                end
            end
        end

        # ===== HARDEN + VERIFY (separate invocations with fix loop) =====
        if not __autoplan_check_skip harden_verify
            __autoplan_save_state $current_plan harden_verify $pr_title
            set -l verify_pass 0

            while true
                set verify_pass (math $verify_pass + 1)
                if test $verify_pass -gt $max_verify_passes
                    echo "⚠️  Verify still finding issues after $max_verify_passes passes." >&2
                    read -P "Continue cycling verify passes? [y/N] " -l _continue_verify
                    if string match -qi 'y*' $_continue_verify
                        set verify_pass 0
                    else
                        return 1
                    end
                end

                echo ""
                echo "🔨 Harden (pass $verify_pass/$max_verify_passes)..."

                rm -f $__autoplan_root/tmp/autoplan-verify-result.txt

                set -l harden_sub (__autoplan_build_user_prompt \
                    harden-prompt.md DOMAIN_HARDEN harden \
                    "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$harden_system_prompt" "$harden_sub"

                echo ""
                echo "🔎 Verify (audit-only, pass $verify_pass/$max_verify_passes)..."

                set -l verify_sub (__autoplan_build_user_prompt \
                    verify-prompt.md DOMAIN_VERIFY verify \
                    "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$verify_system_prompt" "$verify_sub"

                if not test -f $__autoplan_root/tmp/autoplan-verify-result.txt
                    echo "❌ Verify did not write sentinel file." >&2
                    return 1
                end

                if head -1 $__autoplan_root/tmp/autoplan-verify-result.txt | string match -qr '^ALL_GOOD'
                    echo "✅ Verify passed."
                    break
                else if head -1 $__autoplan_root/tmp/autoplan-verify-result.txt | string match -qr '^ISSUES_FOUND'
                    echo "⚠️  Verify found issues. Fixing..."

                    set -l fix_verify_prompt (__autoplan_build_user_prompt \
                        fix-verify-prompt.md DOMAIN_FIX_VERIFY fix_verify \
                        "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                    env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$fix_verify_system_prompt" "/plan $fix_verify_prompt"

                    # Reset fix attempts and go back through test/fix loop
                    set fix_attempt 0
                    while true
                        echo ""
                        echo "🧪 Re-running tests after verify fix..."

                        if __autoplan_run_tests $plan_cwd "$test_cmd" $__autoplan_root/tmp/autoplan-test-output.txt "$manual_test_file" $env_files
                            echo "✅ Tests pass."
                            break
                        else
                            set fix_attempt (math $fix_attempt + 1)
                            if test $fix_attempt -ge $max_fix_attempts
                                echo "⚠️  Tests still failing after $max_fix_attempts fix attempts." >&2
                                echo "Test output: $__autoplan_root/tmp/autoplan-test-output.txt" >&2
                                read -P "Continue cycling fix attempts? [y/N] " -l _continue_fix
                                if string match -qi 'y*' $_continue_fix
                                    set fix_attempt 0
                                else
                                    return 1
                                end
                            end

                            echo "⚠️  Tests failing (attempt $fix_attempt/$max_fix_attempts). Fixing..."

                            set -l refix_prompt (__autoplan_build_user_prompt \
                                fix-test-prompt.md DOMAIN_FIX_TEST fix_test \
                                "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                            env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$fix_test_system_prompt" "/plan $refix_prompt"
                        end
                    end
                    # Continue verify loop
                else
                    echo "❌ Verify did not write a recognized sentinel." >&2
                    return 1
                end
            end
        end

        # ===== VERIFY_CMDS (deterministic harness-driven checks) =====
        if not __autoplan_check_skip verify_cmds
            __autoplan_save_state $current_plan verify_cmds $pr_title

            set -l verify_cmds (__autoplan_frontmatter_list $current_plan verify_cmds)
            if test (count $verify_cmds) -gt 0
                set -l vc_env_prefix (__autoplan_env_prefix $env_files | string collect --allow-empty)
                set -l vc_attempt 0
                while true
                    set -l vc_failed_cmd ""
                    set -l vc_failed_status 0
                    for vc in $verify_cmds
                        echo ""
                        echo "▶ verify_cmd: $vc_env_prefix$vc"
                        env -C $plan_cwd CI=true fish -c $vc_env_prefix$vc >$__autoplan_root/tmp/autoplan-verify-cmd-raw.txt 2>&1
                        set vc_failed_status $status
                        cat $__autoplan_root/tmp/autoplan-verify-cmd-raw.txt
                        if test $vc_failed_status -ne 0
                            set vc_failed_cmd $vc
                            break
                        end
                    end

                    if test -z "$vc_failed_cmd"
                        echo "✅ verify_cmds all passed."
                        rm -f $__autoplan_root/tmp/autoplan-verify-cmd-raw.txt
                        break
                    end

                    set vc_attempt (math $vc_attempt + 1)
                    if test $vc_attempt -ge $max_fix_attempts
                        echo "⚠️  verify_cmd '$vc_failed_cmd' still failing after $max_fix_attempts fix attempts." >&2
                        echo "Log: $__autoplan_root/tmp/autoplan-verify-cmd-output.txt" >&2
                        read -P "Continue cycling fix attempts? [y/N] " -l _continue_vc
                        if string match -qi 'y*' $_continue_vc
                            set vc_attempt 0
                        else
                            return 1
                        end
                    end

                    echo "## Failing command" >$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    echo "$vc_failed_cmd" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    echo "" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    echo "## Output" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    cat $__autoplan_root/tmp/autoplan-verify-cmd-raw.txt >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    rm -f $__autoplan_root/tmp/autoplan-verify-cmd-raw.txt

                    echo "⚠️  verify_cmd failing (attempt $vc_attempt/$max_fix_attempts). Fixing..."

                    set -l fix_vc_prompt (__autoplan_build_user_prompt \
                        fix-verify-cmd-prompt.md DOMAIN_FIX_VERIFY_CMD fix_verify_cmd \
                        "$prompts_path" $current_plan $branch $test_cmd | string collect --allow-empty)

                    env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$fix_verify_cmd_system_prompt" --model sonnet "/plan $fix_vc_prompt"
                end
            end
        end

        # ===== PRE-COMMIT CLEANUP =====
        # Determine if the prompts file is safe to delete (not shared with other plans)
        set -l plan_dir (dirname $current_plan)
        set -l should_delete false
        if test -n "$prompts_path" -a -f "$prompts_path"
            set should_delete true
            set -l canonical_prompts (realpath $prompts_path)
            for f in $plan_dir/*.md
                test (realpath $f) = (realpath $current_plan); and continue
                set -l other_prompts (__autoplan_frontmatter $f prompts)
                test -z "$other_prompts"; and continue
                if not string match -q '/*' $other_prompts
                    set other_prompts (dirname $f)/$other_prompts
                end
                if test (realpath $other_prompts 2>/dev/null) = "$canonical_prompts"
                    set should_delete false
                    break
                end
            end
        end

        # Save next plan path and commit_msg BEFORE deleting plan file
        set -l next_plan (__autoplan_frontmatter $current_plan next)
        set -l commit_msg (__autoplan_frontmatter $current_plan commit_msg)

        # Delete manual_test instructions file
        if test -n "$manual_test_file" -a -f "$manual_test_file"
            rm $manual_test_file
            echo "🗑  Removed manual test instructions: $manual_test_file"
        end

        # Delete plan and prompts files (live at run root, not in sub-repo; harness owns removal)
        rm -f $current_plan
        echo "🗑  Removed completed plan: $current_plan"
        if test "$should_delete" = true
            rm -f $prompts_path
            echo "🗑  Removed prompts file: $prompts_path"
        end

        # ===== COMMIT =====
        if not __autoplan_check_skip commit
            __autoplan_save_state $current_plan commit $pr_title
            echo ""
            echo "💾 Commit..."

            if test -n "$commit_msg"
                if test -n "$(git -C $plan_cwd status --porcelain)"
                    git -C $plan_cwd add -A
                    git -C $plan_cwd commit -m "$commit_msg"
                else
                    echo "ℹ️  Nothing to commit."
                end
            else
                # Fallback: no commit_msg in frontmatter → let Haiku author the commit
                set -l commit_prompt (__autoplan_interpolate_prompt \
                    (cat "$HOME/.claude/skills/autoplan/references/commit-prompt.md") \
                    $current_plan $branch $test_cmd)
                env -C $plan_cwd claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model haiku --effort medium "$commit_prompt"
            end
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
            # Update state so --continue resumes at the next plan's implement
            __autoplan_save_state $current_plan implement $pr_title
        else
            break
        end
    end

    # ===== CHAIN REVIEW + PR (combined orchestrator) =====
    __autoplan_save_state $current_plan chain_review_pr $pr_title
    if not __autoplan_check_skip chain_review_pr
        echo ""
        echo "🔍🚀 Chain review + PR orchestrator..."

        # Re-read branch and cd into the final plan's repo
        set -l branch (__autoplan_frontmatter $current_plan branch)
        set -l final_cwd_raw (__autoplan_frontmatter $current_plan cwd)
        if test -z "$final_cwd_raw"
            set final_cwd_raw .
        end
        set -l final_cwd
        if string match -q '/*' $final_cwd_raw
            set final_cwd $final_cwd_raw
        else
            set final_cwd $__autoplan_root/$final_cwd_raw
        end
        set final_cwd (realpath $final_cwd 2>/dev/null)
        if test -d "$final_cwd"
            __autoplan_activate_tools $final_cwd
        end
        # Adopt-current: if branch omitted or <current>, resolve from actual checkout
        if test -z "$branch"; or test "$branch" = "<current>"
            set branch (git -C $final_cwd branch --show-current 2>/dev/null)
        end

        set -l plan_dir (dirname $current_plan)
        rm -f $__autoplan_root/tmp/autoplan-pr-body.txt

        if test -n "$pr_title"
            set -l pr_body_sub (__autoplan_interpolate_prompt \
                (cat "$HOME/.claude/skills/autoplan/references/pr-body-prompt.md") \
                $current_plan $branch $test_cmd)

            set -l team_slug (string sub -l 52 -- (string replace -ra '[^A-Za-z0-9_-]' '-' -- $branch))
            set -l team_name "autoplan-cr-$team_slug"
            set -l cr_orch (cat "$HOME/.claude/skills/autoplan/references/chain-review-pr-orchestrator.md" \
                | string replace -a -- '$PLAN_FILE' "$current_plan" \
                | string replace -a -- '$BRANCH' "$branch" \
                | string replace -a -- '$PLAN_DIR' "$plan_dir" \
                | string replace -a -- '$PR_BODY_PROMPT' "$pr_body_sub" \
                | string replace -a -- '$TEAM_NAME' "$team_name")

            env -C $final_cwd claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort medium "$cr_orch"

            git -C $final_cwd push origin $branch

            if not test -s $__autoplan_root/tmp/autoplan-pr-body.txt
                echo "⚠️  PR body not generated ($__autoplan_root/tmp/autoplan-pr-body.txt missing/empty); aborting PR create."
            else if gh pr view $branch >/dev/null 2>&1
                echo "PR already exists for $branch."
            else
                gh pr create --title "$pr_title" --body-file $__autoplan_root/tmp/autoplan-pr-body.txt
            end
        else
            # No pr_title — run a git log summary in the final plan's repo (no PR, no cleanup needed)
            set -l review_only_prompt "Review the completed autoplan chain on branch \`$branch\`.

## Review commits
Run: git log --oneline origin/main..$branch
Verify the commits look complete and nothing was obviously missed.

## Summary
Print a brief summary of what was completed and flag anything that looks incomplete."

            env -C $final_cwd claude --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model sonnet --effort medium "$review_only_prompt"
            echo "ℹ️  No pr_title — skipping PR creation."
        end
    end

    # ===== CLEANUP =====
    rm -f $__autoplan_root/tmp/autoplan-*
    rm -f $__autoplan_root/.autoplan-progress

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Autoplan complete."
    return 0
end

# --- Helper functions ---

function __autoplan_compose_system --description "Concatenate prompt-block files into a single system prompt"
    set -l dir "$HOME/.config/fish/functions/autoplan_prompts"
    set -l parts
    for name in $argv
        set -a parts (cat "$dir/$name.md")
        set -a parts ""
    end
    string join \n -- $parts
end

function __autoplan_frontmatter --argument-names plan_file key --description "Extract a frontmatter value from a plan file"
    sed -n '/^---$/,/^---$/p' $plan_file | grep "^$key:" | sed "s/^$key: *//" | tr -d '"' | string trim
end

function __autoplan_frontmatter_list --argument-names plan_file key --description "Extract a YAML list frontmatter value (one shell command per line)"
    # Reads the frontmatter block between the first two `---` lines.
    # Matches a key followed by `:` on its own line (no inline value), then
    # collects subsequent lines starting with `  - ` (2-space indent + dash)
    # until any other top-level frontmatter key or the closing `---`.
    sed -n '/^---$/,/^---$/p' $plan_file | awk -v k="$key" '
        $0 == k ":" { collecting = 1; next }
        collecting && /^  *- / {
            sub(/^  *- */, "", $0)
            print
            next
        }
        collecting && (/^[A-Za-z_][A-Za-z0-9_]*:/ || /^---$/) { collecting = 0 }
    ' | sed 's/^"\(.*\)"$/\1/'
end

function __autoplan_load_prompt --argument-names prompts_file stage --description "Load a prompt section from a prompts file"
    if test -z "$prompts_file" -o ! -f "$prompts_file"
        return
    end
    # Extract from ## stage to next ## header (inclusive), drop header lines
    sed -n "/^## $stage\$/,/^## /p" $prompts_file | sed '1d' | grep -v '^## '
end

function __autoplan_build_user_prompt --description "Build a phase user prompt: load reference template, substitute DOMAIN section + vars"
    # Usage: __autoplan_build_user_prompt <ref-filename> <domain-var-name> <section> <prompts_path> <plan_file> <branch> <test_cmd>
    set -l ref_name $argv[1]
    set -l domain_var $argv[2]
    set -l section $argv[3]
    set -l prompts_path $argv[4]
    set -l plan_file $argv[5]
    set -l branch $argv[6]
    set -l test_cmd $argv[7]

    set -l domain_lines (__autoplan_load_prompt "$prompts_path" $section)
    set -l domain_text (string join \n -- $domain_lines | string collect)
    if test -z "$domain_text"
        set domain_text "(none — this plan supplies no domain-specific context for the $section phase)"
    end

    set -l body (cat "$HOME/.claude/skills/autoplan/references/$ref_name" \
        | string replace -a -- "\$$domain_var" "$domain_text" \
        | string collect --allow-empty)
    __autoplan_interpolate_prompt "$body" $plan_file $branch $test_cmd
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
        | string replace -a -- '$TEST_LOG' "$__autoplan_root/tmp/autoplan-test-output.txt" \
        | string replace -a -- '$VERIFY_LOG' "$__autoplan_root/tmp/autoplan-verify-result.txt" \
        | string replace -a -- '$BRANCH' "$branch_name" \
        | string replace -a -- '$TEST_CMD' "$test_cmd_val" \
        | string replace -a -- '$VERIFY_CMD_LOG' "$__autoplan_root/tmp/autoplan-verify-cmd-output.txt"
end

function __autoplan_run_tests --argument-names plan_cwd test_cmd output_file manual_test_file --description "Run test command(s), then optional manual test; extra args are env_files for dotenvx"
    set -l env_prefix (__autoplan_env_prefix $argv[5..-1] | string collect --allow-empty)
    echo -n >$output_file
    if test -n "$test_cmd"
        echo "# Auto Tests" >>$output_file
        echo "=====" >>$output_file
        for cmd in (string split '&&' -- $test_cmd)
            set cmd (string trim $cmd)
            test -z "$cmd"; and continue
            echo "▶ $env_prefix$cmd" | tee -a $output_file
            env -C $plan_cwd fish -c $env_prefix$cmd 2>&1 | tee -a $output_file
            if test $pipestatus[1] -ne 0
                return 1
            end
        end
    end
    if test -n "$manual_test_file"
        echo "" >>$output_file
        echo "# Manual Test Output" >>$output_file
        echo "=====" >>$output_file
        echo "▶ manual_test $manual_test_file" | tee -a $output_file
        env -C $plan_cwd fish -c "manual_test $manual_test_file" 2>&1 | tee -a $output_file
        if test $pipestatus[1] -ne 0
            return 1
        end
    end
    return 0
end

function __autoplan_env_prefix --description "Build a 'dotenvx run -f … -- ' command prefix from env file paths (empty if none)"
    if test (count $argv) -eq 0
        return
    end
    set -l flags
    for f in $argv
        set -a flags "-f $f"
    end
    echo "dotenvx run $flags -- "
end

function __autoplan_activate_tools --argument-names plan_cwd --description "Re-apply per-directory mise toolchain via subshell; never changes the main process CWD"
    if type -q mise
        env -C $plan_cwd fish -c "mise hook-env -s fish" | source
    end
end

function __autoplan_save_state --argument-names plan phase pr_title
    echo "plan=$plan" > $__autoplan_root/.autoplan-progress
    echo "phase=$phase" >> $__autoplan_root/.autoplan-progress
    echo "pr_title=$pr_title" >> $__autoplan_root/.autoplan-progress
    set_color brblack
    echo "↩️  Resume from this phase ($phase) with: autoplan --continue"
    set_color normal
end

function __autoplan_phase_index --argument-names phase
    switch $phase
        case implement;       echo 1
        case test_fix;        echo 2
        case harden_verify;   echo 3
        case verify_cmds;     echo 4
        case commit;          echo 5
        case chain_review_pr; echo 6
        case '*';             echo 0
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
