A `verify_cmds` entry failed. Combined command + output at $VERIFY_CMD_LOG. Plan: $PLAN_FILE.

Process rules (fix the underlying code not the verifier, no weakening checks, no modifying verify_cmds, no-commit) are supplied by the harness system prompt. The harness will re-run ALL verify_cmds from the start after your fix.

Domain context for this plan:

$DOMAIN_FIX_VERIFY_CMD

When you have fully completed this task, write exactly `ALL_GOOD` (and nothing else) to `$STEP_LOG`. If you stop early, are interrupted, or cannot complete it, do NOT write `ALL_GOOD` — write a one-line reason to `$STEP_LOG` instead.
