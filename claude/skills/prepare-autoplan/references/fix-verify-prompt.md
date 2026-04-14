The verify step found issues. Read $VERIFY_LOG for the numbered list of problems.

Follow TDD: red -> green -> commit.

## Steps

1. Read each issue in $VERIFY_LOG. Understand what the verifier flagged and why.
2. For each issue:
   a. If it's a missing implementation: write a failing test first (RED), then implement (GREEN).
   b. If it's a code quality issue: fix it directly, then run tests to confirm no regressions.
   c. If it's a missing test: add the test and confirm it passes against the existing implementation.
3. Re-run the full test suite to confirm all tests pass.
4. Commit the fixes with a descriptive gitmoji message.

## Rules

- Do NOT weaken, skip, or remove tests to make issues disappear.
- Do NOT remove validation logic or compile-time checks that the verifier flagged as important.
- Fix missing fields or data by checking the plan spec at $PLAN_FILE — the plan is the source of truth.
- Fix malformed outputs by comparing against the expected shapes defined in the plan.
- Do NOT push or open a PR — the pipeline handles that.
