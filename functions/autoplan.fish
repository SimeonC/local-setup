function autoplan --description "Iterative TDD loop driven by a linked list of markdown plan files"
    argparse 'max-fix-attempts=' 'max-verify-passes=' -- $argv

    # Run-root anchoring: all state/tmp paths are relative to where autoplan is launched
    set -g __autoplan_root $PWD

    set -l max_fix_attempts (set -q _flag_max_fix_attempts; and echo $_flag_max_fix_attempts; or echo 3)
    set -l max_verify_passes (set -q _flag_max_verify_passes; and echo $_flag_max_verify_passes; or echo 3)

    set -l permission_mode bypassPermissions

    # ===== SETUP =====
    set -l current_plan ""
    set -l pr_title ""
    set -l snap_test_cmd ""
    set -l snap_branch ""
    set -l snap_cwd_raw ""
    # Clear any stale global skip_to_phase from a previous run in this session
    set -eg skip_to_phase

    if test (count $argv) -eq 0
        if test -f $__autoplan_root/.autoplan-progress
            # Load state from .autoplan-progress
            for _line in (cat $__autoplan_root/.autoplan-progress)
                set -l _parts (string split -m 1 '=' $_line)
                switch $_parts[1]
                    case plan;      set current_plan $_parts[2]
                    case phase;     set -g skip_to_phase $_parts[2]; set_color brblack; echo "  phase=$skip_to_phase"; set_color normal
                    case pr_title;  set pr_title $_parts[2]
                end
            end
        else
            # No progress file: scan cwd (top-level) + plans/ and docs/ (recursive) for incomplete plan roots
            set -l scan_dirs $__autoplan_root
            for base in plans docs
                test -d $__autoplan_root/$base; or continue
                for d in (find $__autoplan_root/$base -type d 2>/dev/null)
                    set -a scan_dirs $d
                end
            end
            set -l roots
            for d in $scan_dirs
                set -a roots (__autoplan_find_root $d)
            end
            set -l root_count (count $roots)
            if test $root_count -eq 0
                echo "✅ No plans found in cwd, plans/, or docs/ — nothing to continue."
                return 0
            else if test $root_count -eq 1
                set current_plan $roots[1]
            else if test -t 0; and not set -q DEVCONTAINER; and type -q fzf
                set -l base $__autoplan_root
                set -l fzf_items
                for r in $roots
                    set -l desc (__autoplan_frontmatter $r description)
                    if test -n "$desc"
                        set -a fzf_items "$(__autoplan_display_rel $base $r)  — $desc"
                    else
                        set -a fzf_items (__autoplan_display_rel $base $r)
                    end
                end
                set -l chosen_line (printf '%s\n' $fzf_items \
                    | fzf --height=40% --reverse \
                          --header="Select a plan to run (pass a dir to filter)" 2>/dev/null)
                if test $status -ne 0; or test -z "$chosen_line"
                    return 1
                end
                set -l picked (string split -m 1 '  — ' $chosen_line)[1]
                if string match -q '/*' $picked
                    set current_plan $picked
                else
                    set current_plan (realpath $base/$picked)
                end
            else
                echo "Error: Multiple plans found — pass a directory to filter or select interactively:" >&2
                for r in $roots
                    echo "  "(__autoplan_display_rel $__autoplan_root $r) >&2
                end
                return 1
            end
        end
    else if test -d $argv[1]
        # Directory mode: scan that dir only for remaining chain roots
        set -l roots (__autoplan_find_root $argv[1])
        set -l root_count (count $roots)
        if test $root_count -eq 0
            echo "✅ No plans remaining in $argv[1] — chain complete."
            return 0
        else if test $root_count -eq 1
            set current_plan $roots[1]
        else if test -t 0; and not set -q DEVCONTAINER; and type -q fzf
            set -l base (realpath $argv[1])
            set -l fzf_items
            for r in $roots
                set -l desc (__autoplan_frontmatter $r description)
                if test -n "$desc"
                    set -a fzf_items "$(__autoplan_display_rel $base $r)  — $desc"
                else
                    set -a fzf_items (__autoplan_display_rel $base $r)
                end
            end
            set -l chosen_line (printf '%s\n' $fzf_items \
                | fzf --height=40% --reverse \
                      --header="Multiple chain roots found — select one to run" 2>/dev/null)
            if test $status -ne 0; or test -z "$chosen_line"
                return 1
            end
            set -l picked (string split -m 1 '  — ' $chosen_line)[1]
            if string match -q '/*' $picked
                set current_plan $picked
            else
                set current_plan (realpath $base/$picked)
            end
        else
            echo "Error: Multiple chain roots found in $argv[1] — cannot auto-select:" >&2
            for r in $roots
                echo "  "(__autoplan_display_rel (realpath $argv[1]) $r) >&2
            end
            return 1
        end
        # Phase resume: if .autoplan-progress refers to this plan, load phase + pr_title
        if test -f $__autoplan_root/.autoplan-progress
            set -l _progress_plan ""
            set -l _progress_phase ""
            set -l _progress_pr_title ""
            for _line in (cat $__autoplan_root/.autoplan-progress)
                set -l _parts (string split -m 1 '=' $_line)
                switch $_parts[1]
                    case plan;      set _progress_plan $_parts[2]
                    case phase;     set _progress_phase $_parts[2]
                    case pr_title;  set _progress_pr_title $_parts[2]
                end
            end
            set -l _pp_real (realpath $_progress_plan 2>/dev/null)
            if test "$_pp_real" = "$current_plan"
                set -g skip_to_phase $_progress_phase
                set pr_title $_progress_pr_title
                set_color brblack; echo "  phase=$skip_to_phase"; set_color normal
            end
        end
    else
        set current_plan (realpath $argv[1])
        if not test -f $current_plan
            echo "Error: Plan file not found: $argv[1]" >&2
            return 1
        end
    end

    if test -z "$pr_title"
        set pr_title (__autoplan_frontmatter $current_plan pr_title)
    end

    mkdir -p $__autoplan_root/tmp

    set -l base_system_prompt (__autoplan_compose_system base)
    set -l prototype_system_prompt      (__autoplan_compose_system base stage-restrictions prototype)
    set -l implement_system_prompt     (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity implement)
    set -l fix_test_system_prompt      (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-test)
    set -l fix_verify_system_prompt    (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-verify)
    set -l fix_verify_cmd_system_prompt (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm fix-verify-cmd)
    set -l harden_system_prompt        (__autoplan_compose_system base stage-restrictions scope no-cmd test-integrity refactor-confirm harden)
    set -l verify_system_prompt        (__autoplan_compose_system base stage-restrictions scope verify)

    # ===== MAIN LOOP (linked list traversal) =====
    while true
        # ===== PER-PLAN VALIDATION =====
        set -l _val_test_cmds (__autoplan_frontmatter_list $current_plan test_cmds)
        set -l _val_manual_test (__autoplan_manual_test_file $current_plan)
        set -l _val_prompts (__autoplan_prompts_path $current_plan)
        set -l _val_env_files (__autoplan_frontmatter_list $current_plan env_files)
        if test (count $_val_test_cmds) -eq 0 -a -z "$_val_manual_test"
            echo "Error: Plan file must have test_cmds, manual_test, or both: $current_plan" >&2
            return 1
        end
        if test -n "$_val_manual_test" -a ! -f "$_val_manual_test"
            echo "Error: manual_test file not found: $_val_manual_test" >&2
            return 1
        end
        if test -n "$_val_prompts" -a ! -f "$_val_prompts"
            echo "Error: prompts file not found: $_val_prompts" >&2
            return 1
        end
        if test (count $_val_env_files) -gt 0; and not type -q dotenvx
            echo "Error: Plan uses env_files but dotenvx is not installed. Install with: brew install dotenvx/brew/dotenvx" >&2
            return 1
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

            # Chooser: only when branch is omitted (explicit `<current>` adopts silently); skip on resume
            if test -z "$branch"; and test -t 0; and not set -q DEVCONTAINER
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
            else if test -z "$branch"; and test -t 0; and not set -q DEVCONTAINER
                and not set -q skip_to_phase
                and not type -q fzf
                echo "note: fzf not installed — adopting current branch '$current_branch' in $plan_cwd (install with: brew install fzf)"
            end

            set branch $current_branch
        else
            # Ensure-branch mode: branch: <name> is specified
            set -l _fresh_start_phase false
            if not set -q skip_to_phase; or test "$skip_to_phase" = prototype; or test "$skip_to_phase" = implement
                set _fresh_start_phase true
            end
            if git -C $plan_cwd show-ref --verify --quiet refs/heads/$branch
                # Branch exists locally — checkout if not current
                if test (git -C $plan_cwd branch --show-current) != $branch
                    git -C $plan_cwd checkout $branch
                end
            else if test "$_fresh_start_phase" = true
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

        # Re-read pr_title per plan
        set pr_title (__autoplan_frontmatter $current_plan pr_title)

        # ===== PROTOTYPE (interactive, opt-in) =====
        if test "$(__autoplan_frontmatter $current_plan prototype)" = true
            if not __autoplan_check_skip prototype
                __autoplan_pause_exit_window; or return 1
                __autoplan_save_state $current_plan prototype $pr_title
                echo "🎨 Prototype (interactive)..."
                set -l sandbox (__autoplan_ensure_prototype_sandbox)
                set -l port (__autoplan_free_port)
                set -l srv_pid (__autoplan_prototype_server_start $sandbox $port)
                if test $status -ne 0
                    echo "⚠️  Failed to start prototype server. Stopping without advancing state. Resume with: autoplan" >&2
                    return 1
                end
                set -l proto_dir $sandbox/src/prototypes
                set -l proto_url "http://localhost:$port"
                set -l _pp (__autoplan_prompts_path $current_plan)
                set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                set -l proto_sub (__autoplan_build_user_prompt \
                    prototype-prompt.md DOMAIN_PROTOTYPE prototype \
                    "$_pp" $current_plan $branch "$_tc" \
                    --proto-dir "$proto_dir" --proto-url "$proto_url" | string collect --allow-empty)
                rm -f $__autoplan_root/tmp/autoplan-step-result.txt
                __autoplan_claude_headed $plan_cwd --name (__autoplan_session_name $current_plan prototype) \
                    --permission-mode $permission_mode --model 'opus[1m]' \
                    --append-system-prompt "$prototype_system_prompt" "$proto_sub"
                set -l _st $__autoplan_last_status
                __autoplan_prototype_server_stop $srv_pid
                if __autoplan_step_failed $_st; return 1; end
                echo "✅ Prototype complete."
            end
        end

        # ===== IMPLEMENT =====
        if not __autoplan_check_skip implement
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan implement $pr_title
            echo "🛠️  Implement..."

            set -l _pp (__autoplan_prompts_path $current_plan)
            set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
            set -l impl_sub (__autoplan_build_user_prompt \
                implement-prompt.md DOMAIN_IMPLEMENT implement \
                "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)

            rm -f $__autoplan_root/tmp/autoplan-step-result.txt
            __autoplan_run_headless $plan_cwd \
                (__autoplan_session_name $current_plan implement) \
                $permission_mode 'opus[1m]' "$implement_system_prompt" "$impl_sub"
            if test $__autoplan_last_status -eq 130
                echo "⚠️  Implement interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                return 1
            end

            set -l _sentinel $__autoplan_root/tmp/autoplan-step-result.txt
            if test -f $_sentinel; and head -1 $_sentinel | string match -qr '^ALL_GOOD'
                echo "✅ Implement complete."
            else
                if test -f $_sentinel
                    cat $_sentinel >&2
                end
                echo "⚠️  Implement incomplete." >&2
                if __autoplan_can_steer
                    __autoplan_resume_headed $plan_cwd $__autoplan_last_uuid $permission_mode \
                        "Implement is not done. Finish the implementation and write ALL_GOOD as the first line of $__autoplan_root/tmp/autoplan-step-result.txt when complete." \
                        true
                    if test $__autoplan_last_status -eq 130
                        echo "⚠️  Implement steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                        return 1
                    end
                    echo "✅ Implement complete."
                else
                    echo "Stopping without advancing state. Resume with: autoplan" >&2
                    return 1
                end
            end
        end

        # ===== TEST/FIX LOOP =====
        # Sequential per-command: run each command independently; fix and re-run only the
        # failing command; advance to the next only after it passes.
        if not __autoplan_check_skip test_fix
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan test_fix $pr_title

            set -l _all_cmds (__autoplan_frontmatter_list $current_plan test_cmds)
            set -l _mf (__autoplan_manual_test_file $current_plan)
            set -l _ef (__autoplan_frontmatter_list $current_plan env_files)
            set -l _env_prefix (__autoplan_env_prefix $_ef | string collect --allow-empty)
            set -l _pp (__autoplan_prompts_path $current_plan)
            set -l _all_tc (string join \n -- $_all_cmds)

            # Run each automated command as an independent checkpoint
            for _cmd in $_all_cmds
                set _cmd (string trim $_cmd)
                test -z "$_cmd"; and continue
                set -l cmd_fix_attempt 0
                set -l cmd_last_fix_uuid ""

                while true
                    echo ""
                    echo "🧪 Running: $_env_prefix$_cmd"
                    echo -n >$__autoplan_root/tmp/autoplan-test-output.txt
                    echo "▶ $_env_prefix$_cmd" | tee -a $__autoplan_root/tmp/autoplan-test-output.txt
                    env -C $plan_cwd fish -c "$_env_prefix$_cmd" 2>&1 | tee -a $__autoplan_root/tmp/autoplan-test-output.txt
                    set -l _cmd_st $pipestatus[1]
                    if test $_cmd_st -eq 130
                        echo "⚠️  Test run interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                        return 1
                    else if test $_cmd_st -eq 0
                        echo "✅ Pass: $_cmd"
                        break
                    else
                        set cmd_fix_attempt (math $cmd_fix_attempt + 1)
                        if test $cmd_fix_attempt -gt $max_fix_attempts
                            echo "⚠️  '$_cmd' still failing after $max_fix_attempts fix attempts." >&2
                            echo "Test output: $__autoplan_root/tmp/autoplan-test-output.txt" >&2
                            if __autoplan_can_steer; and test -n "$cmd_last_fix_uuid"
                                __autoplan_resume_headed $plan_cwd $cmd_last_fix_uuid $permission_mode \
                                    "'$_cmd' is still failing after $max_fix_attempts attempts. Fix the remaining issues. Test output: $__autoplan_root/tmp/autoplan-test-output.txt" \
                                    true
                                if test $__autoplan_last_status -eq 130
                                    echo "⚠️  Fix steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                                    return 1
                                end
                                set cmd_fix_attempt 0
                                continue
                            else
                                return 1
                            end
                        end

                        echo "⚠️  '$_cmd' failing (attempt $cmd_fix_attempt/$max_fix_attempts). Fixing..."

                        set -l fix_prompt (__autoplan_build_user_prompt \
                            fix-test-prompt.md DOMAIN_FIX_TEST fix_test \
                            "$_pp" $current_plan $branch "$_all_tc" | string collect --allow-empty)

                        __autoplan_run_headless $plan_cwd \
                            (__autoplan_session_name $current_plan fix-test) \
                            $permission_mode "" "$fix_test_system_prompt" "$fix_prompt"
                        set cmd_last_fix_uuid $__autoplan_last_uuid
                        if test $__autoplan_last_status -eq 130
                            echo "⚠️  Fix interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                            return 1
                        end
                    end
                end
            end

            # Run manual test after all automated commands pass
            if test -n "$_mf"
                set -l mt_fix_attempt 0
                set -l mt_last_fix_uuid ""
                while true
                    echo ""
                    echo "🧪 Running manual test: $_mf"
                    echo -n >$__autoplan_root/tmp/autoplan-test-output.txt
                    echo "▶ manual_test $_mf" | tee -a $__autoplan_root/tmp/autoplan-test-output.txt
                    env -C $plan_cwd fish -c "manual_test $_mf" 2>&1 | tee -a $__autoplan_root/tmp/autoplan-test-output.txt
                    set -l _mt_st $pipestatus[1]
                    if test $_mt_st -eq 130
                        echo "⚠️  Test run interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                        return 1
                    else if test $_mt_st -eq 0
                        echo "✅ Manual test pass."
                        break
                    else
                        set mt_fix_attempt (math $mt_fix_attempt + 1)
                        if test $mt_fix_attempt -gt $max_fix_attempts
                            echo "⚠️  Manual test still failing after $max_fix_attempts fix attempts." >&2
                            echo "Test output: $__autoplan_root/tmp/autoplan-test-output.txt" >&2
                            if __autoplan_can_steer; and test -n "$mt_last_fix_uuid"
                                __autoplan_resume_headed $plan_cwd $mt_last_fix_uuid $permission_mode \
                                    "Manual test is still failing after $max_fix_attempts attempts. Fix the remaining issues. Test output: $__autoplan_root/tmp/autoplan-test-output.txt" \
                                    true
                                if test $__autoplan_last_status -eq 130
                                    echo "⚠️  Fix steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                                    return 1
                                end
                                set mt_fix_attempt 0
                                continue
                            else
                                return 1
                            end
                        end

                        echo "⚠️  Manual test failing (attempt $mt_fix_attempt/$max_fix_attempts). Fixing..."

                        set -l fix_prompt (__autoplan_build_user_prompt \
                            fix-test-prompt.md DOMAIN_FIX_TEST fix_test \
                            "$_pp" $current_plan $branch "$_all_tc" | string collect --allow-empty)

                        __autoplan_run_headless $plan_cwd \
                            (__autoplan_session_name $current_plan fix-test) \
                            $permission_mode "" "$fix_test_system_prompt" "$fix_prompt"
                        set mt_last_fix_uuid $__autoplan_last_uuid
                        if test $__autoplan_last_status -eq 130
                            echo "⚠️  Fix interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                            return 1
                        end
                    end
                end
            end

            echo "✅ All tests pass."
        end

        # ===== HARDEN + VERIFY (separate invocations with fix loop) =====
        if not __autoplan_check_skip harden_verify
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan harden_verify $pr_title
            set -l verify_pass 0

            while true
                set verify_pass (math $verify_pass + 1)
                if test $verify_pass -gt $max_verify_passes
                    echo "⚠️  Verify still finding issues after $max_verify_passes passes. Resume with: autoplan" >&2
                    return 1
                end

                echo ""
                echo "🔨 Harden (pass $verify_pass/$max_verify_passes)..."

                rm -f $__autoplan_root/tmp/autoplan-verify-result.txt

                set -l _pp (__autoplan_prompts_path $current_plan)
                set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                set -l harden_sub (__autoplan_build_user_prompt \
                    harden-prompt.md DOMAIN_HARDEN harden \
                    "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)

                rm -f $__autoplan_root/tmp/autoplan-step-result.txt
                __autoplan_run_headless $plan_cwd \
                    (__autoplan_session_name $current_plan harden) \
                    $permission_mode "" "$harden_system_prompt" "$harden_sub"
                set -l _harden_uuid $__autoplan_last_uuid
                if test $__autoplan_last_status -eq 130
                    echo "⚠️  Harden interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                    return 1
                end
                if not test -f $__autoplan_root/tmp/autoplan-step-result.txt; \
                        or not head -1 $__autoplan_root/tmp/autoplan-step-result.txt | string match -qr '^ALL_GOOD'
                    if test -f $__autoplan_root/tmp/autoplan-step-result.txt
                        cat $__autoplan_root/tmp/autoplan-step-result.txt >&2
                    end
                    echo "⚠️  Harden incomplete." >&2
                    if __autoplan_can_steer
                        __autoplan_resume_headed $plan_cwd $_harden_uuid $permission_mode \
                            "Harden is not done. Complete all harden tasks and write ALL_GOOD as the first line of $__autoplan_root/tmp/autoplan-step-result.txt when complete." \
                            true
                        if test $__autoplan_last_status -eq 130
                            echo "⚠️  Harden steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                            return 1
                        end
                    else
                        echo "Stopping without advancing state. Resume with: autoplan" >&2
                        return 1
                    end
                end

                echo ""
                echo "🔎 Verify (audit-only, pass $verify_pass/$max_verify_passes)..."

                set -l _pp (__autoplan_prompts_path $current_plan)
                set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                set -l verify_sub (__autoplan_build_user_prompt \
                    verify-prompt.md DOMAIN_VERIFY verify \
                    "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)

                __autoplan_claude_headed $plan_cwd \
                    --name (__autoplan_session_name $current_plan verify) \
                    --permission-mode $permission_mode \
                    --append-system-prompt "$verify_system_prompt" "$verify_sub"
                if test $__autoplan_last_status -eq 130
                    echo "⚠️  Verify interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                    return 1
                end

                if not test -f $__autoplan_root/tmp/autoplan-verify-result.txt
                    echo "⚠️  Verify left no sentinel. Stopping. Resume with: autoplan" >&2
                    return 1
                end

                if head -1 $__autoplan_root/tmp/autoplan-verify-result.txt | string match -qr '^ALL_GOOD'
                    echo "✅ Verify passed."
                    break
                else if head -1 $__autoplan_root/tmp/autoplan-verify-result.txt | string match -qr '^ISSUES_FOUND'
                    echo "⚠️  Verify found issues. Fixing..."

                    set -l _pp (__autoplan_prompts_path $current_plan)
                    set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                    set -l fix_verify_prompt (__autoplan_build_user_prompt \
                        fix-verify-prompt.md DOMAIN_FIX_VERIFY fix_verify \
                        "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)

                    __autoplan_claude_headed $plan_cwd --name (__autoplan_session_name $current_plan fix-verify) --permission-mode $permission_mode --append-system-prompt "$fix_verify_system_prompt" "/plan $fix_verify_prompt"
                    set -l _st $__autoplan_last_status
                    if __autoplan_step_interrupted $_st; return 1; end

                    # Re-run all tests after verify fix (using existing run_tests helper)
                    set -l refix_attempt 0
                    set -l refix_last_uuid ""
                    while true
                        echo ""
                        echo "🧪 Re-running tests after verify fix..."
                        set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                        set -l _mf (__autoplan_manual_test_file $current_plan)
                        set -l _ef (__autoplan_frontmatter_list $current_plan env_files)
                        __autoplan_run_tests $plan_cwd "$_tc" $__autoplan_root/tmp/autoplan-test-output.txt "$_mf" $_ef
                        set -l _rerun_st $status
                        if test $_rerun_st -eq 0
                            echo "✅ Tests pass."
                            break
                        else if test $_rerun_st -eq 130
                            echo "⚠️  Test run interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                            return 1
                        else
                            set refix_attempt (math $refix_attempt + 1)
                            if test $refix_attempt -gt $max_fix_attempts
                                echo "⚠️  Tests still failing after $max_fix_attempts fix attempts." >&2
                                echo "Test output: $__autoplan_root/tmp/autoplan-test-output.txt" >&2
                                if __autoplan_can_steer; and test -n "$refix_last_uuid"
                                    __autoplan_resume_headed $plan_cwd $refix_last_uuid $permission_mode \
                                        "Tests are still failing after $max_fix_attempts attempts. Fix the remaining issues. Test output: $__autoplan_root/tmp/autoplan-test-output.txt" \
                                        true
                                    if test $__autoplan_last_status -eq 130
                                        echo "⚠️  Fix steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                                        return 1
                                    end
                                    set refix_attempt 0
                                    continue
                                else
                                    return 1
                                end
                            end
                            echo "⚠️  Tests failing (attempt $refix_attempt/$max_fix_attempts). Fixing..."
                            set -l _pp (__autoplan_prompts_path $current_plan)
                            set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                            set -l refix_prompt (__autoplan_build_user_prompt \
                                fix-test-prompt.md DOMAIN_FIX_TEST fix_test \
                                "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)
                            __autoplan_run_headless $plan_cwd \
                                (__autoplan_session_name $current_plan fix-test) \
                                $permission_mode "" "$fix_test_system_prompt" "$refix_prompt"
                            set refix_last_uuid $__autoplan_last_uuid
                            if test $__autoplan_last_status -eq 130
                                echo "⚠️  Fix interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                                return 1
                            end
                        end
                    end
                    # Continue verify loop
                else
                    echo "⚠️  Verify wrote an unrecognized sentinel. Stopping. Resume with: autoplan" >&2
                    return 1
                end
            end
        end

        # ===== VERIFY_CMDS (all-run over test_cmds with CI=true, aggregate report) =====
        # Runs every test_cmds command regardless of earlier failures, emits per-command
        # PASS/FAIL markers, then on any failure calls fix_verify_cmd once with the
        # bundled report and repeats the full run up to max_fix_attempts.
        if not __autoplan_check_skip verify_cmds
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan verify_cmds $pr_title

            set -l _vc_cmds (__autoplan_frontmatter_list $current_plan test_cmds)
            if test (count $_vc_cmds) -gt 0
                set -l _ef (__autoplan_frontmatter_list $current_plan env_files)
                set -l vc_env_prefix (__autoplan_env_prefix $_ef | string collect --allow-empty)
                set -l vc_attempt 0
                set -l last_vc_uuid ""
                while true
                    set -l vc_any_failed false
                    echo "" >$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                    echo "# Verify Run — CI=true all-commands" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt

                    for vc in $_vc_cmds
                        echo ""
                        echo "▶ CI=true $vc_env_prefix$vc"
                        echo "" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                        echo "## Command: $vc" >>$__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                        env -C $plan_cwd CI=true fish -c "$vc_env_prefix$vc" 2>&1 | tee -a $__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                        set -l _vc_st $pipestatus[1]
                        if test $_vc_st -eq 130
                            echo "⚠️  verify_cmds interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                            return 1
                        end
                        if test $_vc_st -eq 0
                            echo "PASS: $vc" | tee -a $__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                        else
                            echo "FAIL: $vc (exit $_vc_st)" | tee -a $__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                            set vc_any_failed true
                        end
                    end

                    if test "$vc_any_failed" = false
                        echo "✅ verify_cmds all passed."
                        rm -f $__autoplan_root/tmp/autoplan-verify-cmd-output.txt
                        break
                    end

                    set vc_attempt (math $vc_attempt + 1)
                    if test $vc_attempt -gt $max_fix_attempts
                        echo "⚠️  verify_cmds still failing after $max_fix_attempts fix attempts." >&2
                        echo "Log: $__autoplan_root/tmp/autoplan-verify-cmd-output.txt" >&2
                        if __autoplan_can_steer; and test -n "$last_vc_uuid"
                            __autoplan_resume_headed $plan_cwd $last_vc_uuid $permission_mode \
                                "verify_cmds still failing after $max_fix_attempts attempts. Fix all failing commands. See aggregate report: $__autoplan_root/tmp/autoplan-verify-cmd-output.txt" \
                                true
                            if test $__autoplan_last_status -eq 130
                                echo "⚠️  Fix steer interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                                return 1
                            end
                            set vc_attempt 0
                            continue
                        else
                            return 1
                        end
                    end

                    echo "⚠️  verify_cmds failing (attempt $vc_attempt/$max_fix_attempts). Fixing..."

                    set -l _pp (__autoplan_prompts_path $current_plan)
                    set -l _tc (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
                    set -l fix_vc_prompt (__autoplan_build_user_prompt \
                        fix-verify-cmd-prompt.md DOMAIN_FIX_VERIFY_CMD fix_verify_cmd \
                        "$_pp" $current_plan $branch "$_tc" | string collect --allow-empty)

                    __autoplan_run_headless $plan_cwd \
                        (__autoplan_session_name $current_plan fix-verify-cmd) \
                        $permission_mode "" "$fix_verify_cmd_system_prompt" "$fix_vc_prompt"
                    set last_vc_uuid $__autoplan_last_uuid
                    if test $__autoplan_last_status -eq 130
                        echo "⚠️  Fix interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                        return 1
                    end
                end
            end
        end

        # ===== PRE-COMMIT CLEANUP =====
        # Determine if the prompts file is safe to delete (not shared with other plans)
        set -l plan_dir (dirname $current_plan)
        set -l prompts_path (__autoplan_prompts_path $current_plan)
        set -l manual_test_file (__autoplan_manual_test_file $current_plan)
        set -l should_delete false
        if test -n "$prompts_path" -a -f "$prompts_path"
            set should_delete true
            set -l canonical_prompts (realpath $prompts_path)
            for f in $plan_dir/*.md
                test (realpath $f) = (realpath $current_plan); and continue
                string match -q '*-prompts.md' $f; and continue
                string match -q '*.manual.md' $f; and continue
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

        # Save next plan path, commit_msg, and snapshots BEFORE deleting plan file
        set -l next_plan (__autoplan_frontmatter $current_plan next)
        set -l commit_msg (__autoplan_frontmatter $current_plan commit_msg)
        set snap_test_cmd (string join \n -- (__autoplan_frontmatter_list $current_plan test_cmds))
        set snap_branch   (__autoplan_frontmatter $current_plan branch)
        set snap_cwd_raw  (__autoplan_frontmatter $current_plan cwd)

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
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan commit $pr_title
            echo ""
            echo "💾 Commit..."

            set -l _commit_log $__autoplan_root/tmp/autoplan-commit-output.txt

            if test -n "$commit_msg"
                if test -n "$(git -C $plan_cwd status --porcelain)"
                    git -C $plan_cwd add -A
                    git -C $plan_cwd commit -m "$commit_msg" 2>&1 | tee $_commit_log
                    set -l _commit_st $pipestatus[1]
                    if test $_commit_st -ne 0
                        echo "⚠️  Commit failed (likely pre-commit hooks). Recovering..." >&2
                        __autoplan_commit_recover $plan_cwd $current_plan $branch "$snap_test_cmd" "$commit_msg" $permission_mode "$base_system_prompt"
                        or return 1
                    end
                else
                    echo "ℹ️  Nothing to commit."
                end
            else
                # Fallback: no commit_msg in frontmatter → let Haiku author the commit
                set -l commit_prompt (__autoplan_interpolate_prompt \
                    (cat "$HOME/.claude/skills/autoplan/references/commit-prompt.md") \
                    $current_plan $branch $snap_test_cmd)
                rm -f $__autoplan_root/tmp/autoplan-step-result.txt
                env -C $plan_cwd claude -p --output-format stream-json --verbose \
                    --name (__autoplan_session_name $current_plan commit) \
                    --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" \
                    --model haiku --effort medium "$commit_prompt" | format-claude-stream | tee $_commit_log
                set -l _st $pipestatus[1]
                if test $_st -eq 130
                    echo "⚠️  Step interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                    return 1
                end
                if not test -f $__autoplan_root/tmp/autoplan-step-result.txt; \
                    or not head -1 $__autoplan_root/tmp/autoplan-step-result.txt | string match -qr '^ALL_GOOD'
                    echo "⚠️  Haiku commit step failed. Attempting headed recovery..." >&2
                    __autoplan_commit_recover $plan_cwd $current_plan $branch "$snap_test_cmd" "" $permission_mode "$base_system_prompt"
                    or return 1
                end
            end
        end

        # ===== CHAIN REVIEW + PR (pr_title plans only) =====
        # Runs on any plan that has a pr_title (PR boundary). State is saved only
        # when we actually enter this phase, so plans without pr_title never record
        # a bogus chain_review_pr resume point.
        if test -n "$pr_title"
            __autoplan_pause_exit_window; or return 1
            __autoplan_save_state $current_plan chain_review_pr $pr_title
        else if test -z "$pr_title"; and set -q skip_to_phase; and test "$skip_to_phase" = chain_review_pr
            # Plan without pr_title resumed at a stale chain_review_pr point: clear
            # the flag so the plan starts cleanly at implement.
            set -eg skip_to_phase
        end
        if test -n "$pr_title"; and not __autoplan_check_skip chain_review_pr
            echo ""
            echo "🔍🚀 Chain review + PR orchestrator..."

            rm -f $__autoplan_root/tmp/autoplan-pr-body.txt

            set -l pr_body_sub (__autoplan_interpolate_prompt \
                (cat "$HOME/.claude/skills/autoplan/references/pr-body-prompt.md") \
                $current_plan $branch $snap_test_cmd)

            set -l team_slug (string sub -l 52 -- (string replace -ra '[^A-Za-z0-9_-]' '-' -- $branch))
            set -l team_name "autoplan-cr-$team_slug"
            set -l cr_orch (cat "$HOME/.claude/skills/autoplan/references/chain-review-pr-orchestrator.md" \
                | string replace -a -- '$PLAN_FILE' "$current_plan" \
                | string replace -a -- '$BRANCH' "$branch" \
                | string replace -a -- '$PLAN_DIR' "$plan_dir" \
                | string replace -a -- '$PR_BODY_PROMPT' "$pr_body_sub" \
                | string replace -a -- '$TEAM_NAME' "$team_name")

            __autoplan_claude_headed $plan_cwd --name (__autoplan_session_name $current_plan chain-review) --permission-mode $permission_mode --append-system-prompt "$base_system_prompt" --model opusplan --effort medium "$cr_orch"
            set -l _cr_st $__autoplan_last_status
            if test $_cr_st -eq 130
                echo "⚠️  Chain review interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
                return 1
            end

            git -C $plan_cwd push origin $branch

            if not test -s $__autoplan_root/tmp/autoplan-pr-body.txt
                echo "⚠️  PR body not generated ($__autoplan_root/tmp/autoplan-pr-body.txt missing/empty); aborting PR create."
            else if gh pr view $branch >/dev/null 2>&1
                echo "PR already exists for $branch."
            else
                gh pr create --title "$pr_title" --body-file $__autoplan_root/tmp/autoplan-pr-body.txt
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
            if test -n "$pr_title"
                # PR boundary: pause for review/merge, save state pointing at next plan
                set current_plan $next_plan
                __autoplan_pause_exit_window; or return 1
                __autoplan_save_state $current_plan implement ""
                echo "⏸️  PR raised — review & merge, then run \`autoplan\` to continue"
                return 0
            else
                # No PR boundary: fold forward into next plan
                set current_plan $next_plan
                __autoplan_pause_exit_window; or return 1
                __autoplan_save_state $current_plan implement $pr_title
            end
        else
            break
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
    yq --front-matter=extract ".$key // \"\"" $plan_file
end

function __autoplan_frontmatter_list --argument-names plan_file key --description "Extract a YAML scalar-or-list frontmatter value (one item per line)"
    yq --front-matter=extract "[.$key] | flatten | .[] | select(. != null)" $plan_file
end

function __autoplan_resolve_rel --argument-names plan_file raw --description "Resolve a path relative to plan_file dir; absolute paths pass through; empty returns empty"
    test -z "$raw"; and return
    if string match -q '/*' $raw
        echo $raw
    else
        echo (dirname $plan_file)/$raw
    end
end

function __autoplan_display_rel --argument-names base abs --description "Display abs relative to base dir; abs passes through if outside base"
    string replace -- "$base/" "" $abs
end

function __autoplan_pause_exit_window --description "Interruptible countdown window to Ctrl-C before advancing; returns 130 if interrupted"
    # Trap SIGINT so Ctrl-C is consumed cleanly (a bare `sleep` would let the
    # signal interrupt fish itself, skipping the caller's `; or return 1`).
    set -g __autoplan_int 0
    function __autoplan_on_sigint --on-signal INT
        set -g __autoplan_int 1
    end
    set_color brblack
    for i in 5 4 3 2 1
        printf '\r  ⏸  advancing in %ds — Ctrl-C to stop ' $i
        sleep 1
        set -l slept $status
        if test "$__autoplan_int" = 1; or test $slept -ne 0
            set __autoplan_int 1
            break
        end
    end
    functions -e __autoplan_on_sigint
    if test "$__autoplan_int" = 1
        set_color normal
        printf '\n'
        return 130
    end
    # Leave a persistent trace so it's clear the window elapsed (the live
    # countdown erases itself; without this, scrollback looks like no pause ran).
    printf '\r\033[K  ⏵  advancing…\n'
    set_color normal
end

function __autoplan_manual_test_file --argument-names plan_file --description "Resolve manual_test frontmatter path relative to plan_file dir"
    __autoplan_resolve_rel $plan_file (__autoplan_frontmatter $plan_file manual_test)
end

function __autoplan_prompts_path --argument-names plan_file --description "Resolve prompts frontmatter path relative to plan_file dir"
    __autoplan_resolve_rel $plan_file (__autoplan_frontmatter $plan_file prompts)
end

function __autoplan_load_prompt --argument-names prompts_file stage --description "Load a prompt section from a prompts file"
    if test -z "$prompts_file" -o ! -f "$prompts_file"
        return
    end
    # Extract from ## stage to next ## header (inclusive), drop header lines
    sed -n "/^## $stage\$/,/^## /p" $prompts_file | sed '1d' | grep -v '^## '
end

function __autoplan_build_user_prompt --description "Build a phase user prompt: load reference template, substitute DOMAIN section + vars"
    # Usage: __autoplan_build_user_prompt <ref> <domain-var> <section> <prompts> <plan_file> <branch> [test_cmd...] [--proto-dir DIR] [--proto-url URL]
    argparse 'proto-dir=' 'proto-url=' -- $argv
    set -l ref_name $argv[1]
    set -l domain_var $argv[2]
    set -l section $argv[3]
    set -l prompts_path $argv[4]
    set -l plan_file $argv[5]
    set -l branch $argv[6]
    # argv[7..-1] are test_cmd lines (0, 1, or many — join safely)
    set -l test_cmd (string join \n -- $argv[7..-1])
    set -l proto_dir (test -n "$_flag_proto_dir"; and echo "$_flag_proto_dir"; or echo "")
    set -l proto_url (test -n "$_flag_proto_url"; and echo "$_flag_proto_url"; or echo "")

    set -l domain_lines (__autoplan_load_prompt "$prompts_path" $section)
    set -l domain_text (string join \n -- $domain_lines | string collect)
    if test -z "$domain_text"
        set domain_text "(none — this plan supplies no domain-specific context for the $section phase)"
    end

    set -l body (cat "$HOME/.claude/skills/autoplan/references/$ref_name" \
        | string replace -a -- "\$$domain_var" "$domain_text" \
        | string collect --allow-empty)

    # Standard variable interpolation (plan_file, branch, test_cmd, log paths)
    set -l interpolated (__autoplan_interpolate_prompt "$body" $plan_file $branch $test_cmd)

    # Prototype-specific substitutions (no-op when empty; harness-only vars not in __autoplan_interpolate_prompt)
    printf '%s\n' $interpolated \
        | string replace -a -- '$PROTOTYPE_DIR' "$proto_dir" \
        | string replace -a -- '$PROTOTYPE_URL' "$proto_url"
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
        | string replace -a -- '$STEP_LOG' "$__autoplan_root/tmp/autoplan-step-result.txt" \
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
        for cmd in (string split \n -- $test_cmd)
            set cmd (string trim $cmd)
            test -z "$cmd"; and continue
            echo "▶ $env_prefix$cmd" | tee -a $output_file
            env -C $plan_cwd fish -c $env_prefix$cmd 2>&1 | tee -a $output_file
            set -l _cmd_st $pipestatus[1]
            if test $_cmd_st -eq 130
                return 130
            else if test $_cmd_st -ne 0
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
        set -l _mt_st $pipestatus[1]
        if test $_mt_st -eq 130
            return 130
        else if test $_mt_st -ne 0
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
    echo "  phase=$phase"
    echo "↩️  Resume from this phase ($phase) with: autoplan"
    set_color normal
end

function __autoplan_step_failed --argument-names exit_status --description "Check if a Claude step failed/was interrupted; prints reason; returns 0=abort 1=ok"
    if test $exit_status -eq 130
        echo "⚠️  Step interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
        return 0
    end
    if not test -f $__autoplan_root/tmp/autoplan-step-result.txt
        echo "⚠️  Step did not write completion sentinel. Stopping without advancing state. Resume with: autoplan" >&2
        return 0
    end
    if not head -1 $__autoplan_root/tmp/autoplan-step-result.txt | string match -qr '^ALL_GOOD'
        echo "⚠️  Step completion sentinel is not ALL_GOOD:" >&2
        cat $__autoplan_root/tmp/autoplan-step-result.txt >&2
        echo "Stopping without advancing state. Resume with: autoplan" >&2
        return 0
    end
    return 1
end

function __autoplan_commit_recover --description "Headed recovery for a failed commit; returns 0 on success, 1 on failure/abort"
    # args: plan_cwd plan_file branch test_cmd commit_msg perm_mode base_system_prompt
    set -l _cr_cwd $argv[1]
    set -l _cr_plan $argv[2]
    set -l _cr_branch $argv[3]
    set -l _cr_test_cmd $argv[4]
    set -l _cr_commit_msg $argv[5]
    set -l _cr_perm $argv[6]
    set -l _cr_base $argv[7]

    set -l _commit_log $__autoplan_root/tmp/autoplan-commit-output.txt

    if not __autoplan_can_steer
        echo "⚠️  Commit failed but cannot open headed session (non-TTY/devcontainer). Resume with: autoplan" >&2
        return 1
    end

    set -l _raw (__autoplan_interpolate_prompt \
        (cat "$HOME/.claude/skills/autoplan/references/commit-recover-prompt.md") \
        $_cr_plan $_cr_branch $_cr_test_cmd)
    set -l _prompt (printf '%s\n' $_raw \
        | string replace -a -- '$COMMIT_LOG' "$_commit_log" \
        | string replace -a -- '$COMMIT_MSG' "$_cr_commit_msg")

    rm -f $__autoplan_root/tmp/autoplan-step-result.txt
    __autoplan_claude_headed $_cr_cwd \
        --name (__autoplan_session_name $_cr_plan commit-recover) \
        --permission-mode $_cr_perm \
        --append-system-prompt "$_cr_base" \
        --model 'opus[1m]' \
        "$_prompt"

    if test $__autoplan_last_status -eq 130
        echo "⚠️  Recovery session interrupted. Stopping without advancing state. Resume with: autoplan" >&2
        return 1
    end

    if not test -f $__autoplan_root/tmp/autoplan-step-result.txt
        echo "⚠️  Recovery session did not write completion sentinel. Stopping without advancing state. Resume with: autoplan" >&2
        return 1
    end
    if not head -1 $__autoplan_root/tmp/autoplan-step-result.txt | string match -qr '^ALL_GOOD'
        echo "⚠️  Recovery session sentinel is not ALL_GOOD. Stopping without advancing state. Resume with: autoplan" >&2
        return 1
    end
    if test -n "$(git -C $_cr_cwd status --porcelain)"
        echo "⚠️  Recovery completed but working tree is not clean — changes not committed. Stopping without advancing state. Resume with: autoplan" >&2
        return 1
    end
    return 0
end

function __autoplan_step_interrupted --argument-names exit_status --description "Abort only on Ctrl-C (130); used for plan-mode fix steps that can't write a sentinel. returns 0=abort 1=ok"
    if test $exit_status -eq 130
        echo "⚠️  Step interrupted (Ctrl-C). Stopping without advancing state. Resume with: autoplan" >&2
        return 0
    end
    return 1
end

function __autoplan_session_name --argument-names plan_file phase --description "Build a claude --name label: <plan-slug> [<phase>]"
    set -l slug (string replace -r '\.md$' '' -- (basename $plan_file))
    set slug (string replace -ra '[^A-Za-z0-9_-]' '-' -- $slug)
    echo "$slug [$phase]"
end

function __autoplan_can_steer --description "True when running in an interactive TTY outside devcontainer"
    test -t 0; and not set -q DEVCONTAINER
end

function __autoplan_run_headless --description "Run headless step with pre-assigned session id; sets globals __autoplan_last_uuid/__autoplan_last_status"
    # args: plan_cwd session_name perm_mode model system_prompt user_prompt
    set -l _hl_cwd $argv[1]
    set -l _hl_name $argv[2]
    set -l _hl_perm $argv[3]
    set -l _hl_model $argv[4]
    set -l _hl_sys $argv[5]
    set -l _hl_prompt $argv[6]
    set -g __autoplan_last_uuid (uuidgen | string lower)
    # Default to interrupted (130): if rapid Ctrl-C interrupts fish before the
    # trailing assignment runs, the caller's 130 check still aborts cleanly
    # instead of crashing on an empty value.
    set -g __autoplan_last_status 130
    if test -n "$_hl_model"
        env -C $_hl_cwd claude -p --output-format stream-json --verbose \
            --session-id $__autoplan_last_uuid --name $_hl_name \
            --permission-mode $_hl_perm --model $_hl_model \
            --append-system-prompt "$_hl_sys" "$_hl_prompt" | format-claude-stream
    else
        env -C $_hl_cwd claude -p --output-format stream-json --verbose \
            --session-id $__autoplan_last_uuid --name $_hl_name \
            --permission-mode $_hl_perm --model "claude-sonnet-4-6" \
            --append-system-prompt "$_hl_sys" "$_hl_prompt" | format-claude-stream
    end
    set -g __autoplan_last_status $pipestatus[1]
end

function __autoplan_claude_headed --description "Run claude headed via the tmux claude wrapper in a given dir; sets __autoplan_last_status"
    set -l _ch_dir $argv[1]
    # Default to interrupted (130) so rapid Ctrl-C that interrupts fish before
    # the trailing assignment leaves a valid status for the caller's 130 check.
    set -g __autoplan_last_status 130
    pushd $_ch_dir
    set -l _ch_args $argv[2..-1]
    if not contains -- --model $_ch_args
        set _ch_args --model claude-sonnet-4-6 $_ch_args
    end
    claude $_ch_args
    set -g __autoplan_last_status $status
    popd
end

function __autoplan_resume_headed --description "Resume a session headed (no -p); sets __autoplan_last_status"
    # args: plan_cwd uuid perm_mode nudge_msg [use_plan_mode=false]
    set -l _rh_cwd $argv[1]
    set -l _rh_uuid $argv[2]
    set -l _rh_perm $argv[3]
    set -l _rh_nudge $argv[4]
    if test (count $argv) -ge 5; and test "$argv[5]" = true
        set _rh_nudge "/plan $_rh_nudge"
    end
    __autoplan_claude_headed $_rh_cwd --resume $_rh_uuid --permission-mode $_rh_perm "$_rh_nudge"
end

function __autoplan_phase_index --argument-names phase
    switch $phase
        case prototype;       echo 1
        case implement;       echo 2
        case test_fix;        echo 3
        case harden_verify;   echo 4
        case verify_cmds;     echo 5
        case commit;          echo 6
        case chain_review_pr; echo 7
        case '*';             echo 0
    end
end

function __autoplan_find_root --argument-names dir --description "Find root plan files in a chain dir: plans with no inbound next: references"
    set -l plan_files
    set -l referenced

    # Collect plan files: have frontmatter, exclude *-prompts.md and *.manual.md
    for f in $dir/*.md
        test -f $f; or continue
        string match -q '*-prompts.md' $f; and continue
        string match -q '*.manual.md' $f; and continue
        # Must have frontmatter (first line is ---)
        set -l first_line (head -1 $f 2>/dev/null)
        test "$first_line" = "---"; or continue
        set -a plan_files (realpath $f)
    end

    # Collect all next: targets as realpaths
    for f in $plan_files
        set -l next_val (__autoplan_frontmatter $f next)
        test -z "$next_val"; and continue
        set -l resolved
        if string match -q '/*' $next_val
            set resolved $next_val
        else
            set resolved (dirname $f)/$next_val
        end
        set -l rp (realpath $resolved 2>/dev/null)
        test -n "$rp"; and set -a referenced $rp
    end

    # Roots = plan files not referenced by any other plan's next:
    for f in $plan_files
        if not contains $f $referenced
            echo $f
        end
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

function __autoplan_mise_prefix --argument-names sandbox --description "Emit 'mise exec -- ' when mise is installed and sandbox has .tool-versions; else empty"
    if type -q mise; and test -f $sandbox/.tool-versions
        echo "mise exec -- "
    end
end

function __autoplan_prototype_sandbox --description "Echo the working sandbox path"
    set -l data_home
    if set -q XDG_DATA_HOME
        set data_home $XDG_DATA_HOME
    else
        set data_home $HOME/.local/share
    end
    echo $data_home/autoplan-prototype
end

function __autoplan_ensure_prototype_sandbox --description "Idempotent: create working sandbox, sync template files, install if needed"
    set -l template $HOME/.config/fish/autoplan_prototype_template
    set -l sandbox (__autoplan_prototype_sandbox)

    mkdir -p $sandbox/src/prototypes

    # Sync template files (copy when missing or template is newer)
    for src in $template/package.json $template/vite.config.js $template/index.html $template/.tool-versions
        set -l dst $sandbox/(basename $src)
        if not test -f $dst; or test $src -nt $dst
            cp $src $dst
        end
    end
    for src in $template/src/main.js $template/src/app.css $template/src/App.svelte
        set -l dst $sandbox/src/(basename $src)
        if not test -f $dst; or test $src -nt $dst
            cp $src $dst
        end
    end
    if not test -f $sandbox/src/prototypes/.gitkeep
        cp $template/src/prototypes/.gitkeep $sandbox/src/prototypes/.gitkeep
    end

    # Install node_modules when missing or package.json was just updated
    set -l pkg_src $template/package.json
    set -l pkg_dst $sandbox/package.json
    set -l nm $sandbox/node_modules
    if not test -d $nm; or test $pkg_src -nt $nm
        echo "📦 Installing prototype sandbox dependencies..." >&2
        set -l mise_prefix (__autoplan_mise_prefix $sandbox)
        env -C $sandbox fish -c "$mise_prefix""pnpm install" >/dev/null
        env -C $sandbox fish -c "$mise_prefix""pnpm approve-builds esbuild @tablecheck/tablekit-tailwind --config.location=project" >/dev/null
    end

    echo $sandbox
end

function __autoplan_free_port --description "Find a free TCP port starting from 5199"
    set -l port 5199
    while nc -z localhost $port 2>/dev/null
        set port (math $port + 1)
    end
    echo $port
end

function __autoplan_prototype_server_start --argument-names sandbox port --description "Wipe prototypes, start Vite dev server, poll until ready, echo pid"
    # Wipe scratch dir (keep .gitkeep)
    for f in $sandbox/src/prototypes/*.svelte
        rm -f $f
    end

    mkdir -p $sandbox/tmp
    set -l log $sandbox/tmp/autoplan-prototype-server.log
    set -l mise_prefix (__autoplan_mise_prefix $sandbox)

    # Start server in background
    env -C $sandbox fish -c "$mise_prefix""pnpm run dev --port $port --strictPort" >$log 2>&1 &
    set -l srv_pid $last_pid

    # Poll until the server responds (up to 30s)
    set -l url "http://localhost:$port"
    set -l attempts 0
    while test $attempts -lt 60
        if curl -sf $url >/dev/null 2>&1
            break
        end
        sleep 0.5
        set attempts (math $attempts + 1)
    end
    if test $attempts -ge 60
        echo "⚠️  Prototype server did not start at $url" >&2
        kill $srv_pid 2>/dev/null
        return 1
    end

    echo $srv_pid
end

function __autoplan_prototype_server_stop --argument-names pid --description "Kill Vite server process tree (descendants then parent); best-effort"
    if test -z "$pid"
        return
    end
    # Collect descendants recursively
    set -l pids_to_kill
    set -l queue $pid
    while test (count $queue) -gt 0
        set -l current $queue[1]
        set queue $queue[2..-1]
        set -a pids_to_kill $current
        for child in (pgrep -P $current 2>/dev/null)
            set -a queue $child
        end
    end
    # Kill in reverse order (leaves first) then parent
    for p in $pids_to_kill[-1..1]
        kill $p 2>/dev/null
    end
end
