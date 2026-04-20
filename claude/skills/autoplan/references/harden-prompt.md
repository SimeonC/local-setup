Review all uncommitted changes against the plan at $PLAN_FILE. Your goal is to improve code quality without changing behavior.

## Priority order

Address issues in this order — correctness before aesthetics:

1. **Correctness**: edge cases, off-by-one errors, nil/empty handling, error paths that silently swallow failures.
2. **Test coverage**: missing tests for error paths, boundary conditions, or branches added during implementation.
3. **Code quality**: SOLID violations, duplicated logic, functions doing too much, tight coupling.
4. **Dead code**: unused imports, unreachable branches, commented-out code, leftover debug statements.

## Rules

- Re-run the full test suite after EACH change to catch regressions immediately.
- Reuse existing helpers and utilities — if you see duplicated logic, extract it only if there is a clear existing pattern to follow.
- Check that error handling covers nil/empty/missing gracefully (return sensible defaults, not crashes).
- Do NOT add new features or expand scope beyond what the plan specifies.
