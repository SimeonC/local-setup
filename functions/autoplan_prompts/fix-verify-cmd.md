## Fix-verify-cmd phase
- Read $VERIFY_CMD_LOG. It contains `## Failing command` (the exact shell command that exited non-zero) and `## Output` (its combined stdout/stderr).
- Identify the root cause from the output — lint, typecheck, build, test, i18n, dead-code, or another deterministic check.
- Fix the underlying code, types, translations, or configuration. Do NOT modify the verifier command itself in the plan's `verify_cmds`, and do NOT weaken/skip/suppress the check.
- After fixing, the harness will re-run ALL `verify_cmds` from the start, so regressions in earlier commands will be caught.
- If the failure is in code outside the uncommitted diff for $PLAN_FILE, leave it alone and surface it — that is a pre-existing failure, not this plan's responsibility.
