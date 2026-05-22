## Deterministic checks are harness-owned, but you MAY verify your own diff
The harness re-runs `verify_cmds` deterministically after this phase, so do NOT
duplicate that work. But you SHOULD confirm the specific change you just made
actually does what you intended.

Forbidden (the harness will run these):
- Full test suite / `npm test` / project-wide test runner with no scope.
- Whole-repo lint, typecheck, or build (`eslint .`, `tsc --noEmit` on the repo, `npm run build`, etc.).
- Chasing regressions outside the uncommitted diff.

Allowed (scoped to what you just changed):
- Run the single test file(s) you wrote or modified to confirm red→green.
- Run lint/typecheck on the specific file(s) you edited (e.g. `eslint path/to/file.ts`, `tsc --noEmit path/to/file.ts`) when you just fixed an issue in that file.
- Re-run the exact failing command from $VERIFY_CMD_LOG / $TEST_LOG narrowed to the affected file(s), to confirm the fix landed before handing back to the harness.

Rule of thumb: if your last edit targeted a specific file or check, you may re-run that specific file/check. Do NOT widen the scope.
