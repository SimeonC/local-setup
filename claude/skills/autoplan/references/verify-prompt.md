Read the plan at $PLAN_FILE. Audit the UNCOMMITTED changes on branch $BRANCH (working tree + staged, not commit history).

The pipeline runs verify BEFORE commit, so all in-scope changes are uncommitted by design. Use `git diff HEAD` and `git status` to see them. Do NOT use `git log` — changes are not in commit history yet. Do NOT flag "uncommitted" / "not yet committed" / "needs to be committed" as issues; committing is a later pipeline step.

YOUR ROLE IS AUDIT-ONLY. Do NOT edit files, stage, commit, push, or open a PR.

## Structural checks

1. **Scope completeness**: Every item in the plan's Scope section is implemented. Cross-reference each scope bullet with actual code changes.
2. **Verification criteria**: Every command listed in the plan's Verification section passes. Run each one and record the result.
3. **Test integrity**: No test files contain skipped tests, `.only` marks, or TODO placeholders. Every new public function has at least one test.
4. **No regressions**: The full test suite passes. No existing tests were broken or modified to accommodate new code.

## Domain checks

5. **Wiring**: New functions, endpoints, or modules are actually called from the appropriate entry points — not just defined but unused.
6. **Error handling**: Nil/empty/missing inputs are handled gracefully at system boundaries.

## Verdict

- If ALL checks pass: write `ALL_GOOD` to $VERIFY_LOG.
- If ANY check fails: write `ISSUES_FOUND` on line 1 of $VERIFY_LOG, followed by a numbered list of specific issues with file paths and line numbers.

