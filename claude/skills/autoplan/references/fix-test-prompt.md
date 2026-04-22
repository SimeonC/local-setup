Tests are failing. Output at $TEST_LOG.

If `$TEST_LOG` contains `MANUAL TEST FAILURE`, the lines below that banner are a human bug report — treat as the authoritative failure description.

Follow TDD: red -> green -> commit.

## Steps

1. Read the test output at $TEST_LOG to understand every failure — error messages, stack traces, assertion mismatches.
2. Identify the root cause of each failure. Is it a missing implementation, wrong return value, incorrect wiring, or a test environment issue?
3. Fix the implementation to make failing tests pass. Apply the simplest correct fix.
4. Re-run the full test suite to confirm all tests pass and no regressions were introduced.
5. Commit the fixes with a descriptive gitmoji message.

## Rules

- Check for compile-time or lint warnings that could block CI.
- Verify that new code is properly wired into existing call chains (e.g., new functions are actually called, new modules are imported).
- If a fix touches shared code, check callers for unintended side effects.
