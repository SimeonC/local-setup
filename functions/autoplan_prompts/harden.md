## Harden phase
- Subject of hardening: every uncommitted change visible in `git diff HEAD`. Improve quality of those changes without altering their behavior.
- Before any change, confirm the file/function is part of the uncommitted diff. If not, leave it alone.
- Priority order, applied within the uncommitted diff only:
  1. **Correctness** — edge cases, off-by-one, nil/empty handling, silently swallowed errors in lines this plan added or changed.
  2. **Test coverage** — missing tests for error paths/branches this plan introduced.
  3. **Code quality** — SOLID violations, duplicated logic, oversized functions in files this plan added or modified.
  4. **Dead code** introduced by this plan — unused imports, unreachable branches, commented-out code, leftover debug.
- Reuse existing helpers — extract only when there is a clear existing pattern AND the duplication is inside the diff.
- You MAY invoke the `dead-code-pass` skill if available.
