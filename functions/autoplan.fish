function autoplan --description "Iterative TDD loop driven by a markdown plan file"
    argparse 'max-iterations=' -- $argv

    # Validate arguments
    if test (count $argv) -eq 0
        echo "Usage: autoplan <plan-file> [--max-iterations N]" >&2
        return 1
    end

    set -l plan_file (realpath $argv[1])
    if not test -f $plan_file
        echo "Error: Plan file not found: $argv[1]" >&2
        return 1
    end

    set -l max_iterations (set -q _flag_max_iterations; and echo $_flag_max_iterations; or echo 6)
    set -l iteration 0

    # Permission flag for devcontainer
    set -l perm_flag
    if set -q DEVCONTAINER
        set perm_flag --dangerously-skip-permissions
    end

    # System prompts for each phase
    set -l gate_system "You are evaluating a plan for automated implementation. Be strict."

    set -l impl_system "Do NOT refactor beyond making tests pass. Do NOT modify the plan file. Do NOT commit."

    set -l harden_system "Do NOT modify the plan file. Do NOT commit."

    set -l verify_system "You must run tests before committing. You must mark exactly one phase done per invocation."

    # ===== PHASE 0: GATE =====
    echo "🔍 Phase 0: Evaluating plan readiness..."

    set -l gate_output (command claude -p $perm_flag --model haiku --effort low \
        --append-system-prompt "$gate_system" \
        "Read plan at $plan_file. Evaluate each phase for: sufficient detail, clear scope, testable outcomes. If any phase too vague, output what's missing. If all automatable, output only \"READY\".")

    if not string match -q "*READY*" $gate_output
        echo "❌ Gate phase rejected. Feedback:" >&2
        echo "$gate_output" >&2
        return 1
    end

    echo "✅ Gate phase passed. Starting iteration loop."

    # ===== MAIN LOOP =====
    while test -f $plan_file
        set iteration (math $iteration + 1)

        if test $iteration -gt $max_iterations
            echo "⚠️  Reached max iterations ($max_iterations). Breaking loop." >&2
            return 1
        end

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Iteration $iteration / $max_iterations"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # ===== PHASE 1: IMPLEMENT (Red/Green) =====
        echo "📝 Phase 1: Implement (TDD Red/Green)..."

        command claude -p $perm_flag --model sonnet --effort high \
            --append-system-prompt "$impl_system" \
            "Read the plan at $plan_file. Find the next incomplete phase. Use /tdd skill — write tests first (RED), then implement to pass (GREEN). Follow SOLID principles."

        if test $status -ne 0
            echo "❌ Phase 1 (Implement) failed. Aborting loop." >&2
            return 1
        end

        # ===== PHASE 2: HARDEN/REFACTOR =====
        echo ""
        echo "🔨 Phase 2: Harden/Refactor..."

        command claude -p $perm_flag --model sonnet --effort high \
            --append-system-prompt "$harden_system" \
            "Review all uncommitted changes for this project. Identify and fix: duplication, inconsistencies, dead code, missing coverage, SOLID violations. Re-run tests after each change. The plan at $plan_file provides context."

        if test $status -ne 0
            echo "⚠️  Phase 2 (Harden/Refactor) failed. Continuing anyway." >&2
        end

        # ===== PHASE 3: VERIFY & COMMIT =====
        echo ""
        echo "✔️  Phase 3: Verify & Commit..."

        command claude -p $perm_flag --model haiku --effort medium \
            --append-system-prompt "$verify_system" \
            "Run ALL tests/checks — fix any failures. Mark the completed phase done in the plan at $plan_file. Commit with a gitmoji message. If ALL phases are now complete: commit removal of the plan file, update any parent plans/docs that reference it to mark completion."

        if test $status -ne 0
            echo "❌ Phase 3 (Verify & Commit) failed. Aborting loop." >&2
            return 1
        end

        # Check if plan file still exists
        if not test -f $plan_file
            break
        end
    end

    # ===== SUMMARY =====
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if not test -f $plan_file
        echo "✅ Autoplan complete — all phases done in $iteration iterations."
        return 0
    else
        echo "⚠️  Autoplan loop exited but plan file still exists."
        return 1
    end
end
