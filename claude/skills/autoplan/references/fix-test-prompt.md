Tests failed. Output at $TEST_LOG.

The log may contain up to two labeled sections:
- `# Auto Tests` — automated suite output (if $TEST_CMD ran).
- `# Manual Test Output` — human tester's report; a `MANUAL TEST FAILURE` banner followed by their freeform failure description is the authoritative description of what went wrong.

Read whichever sections are present. Fix the implementation/template so both pass on the next run.

Follow TDD: red → green → re-run.

## Steps

1. Read the test output at $TEST_LOG to understand every failure — error messages, stack traces, assertion mismatches.
2. Identify the root cause of each failure. Is it a missing implementation, wrong return value, incorrect wiring, or a test environment issue?
3. Fix the implementation to make failing tests pass. Apply the simplest correct fix.
4. Re-run the full test suite to confirm all tests pass and no regressions were introduced.

## Rules

- Do NOT weaken, skip, disable, or remove tests.
- Do NOT modify manual test instruction files — they are the spec.
- Check for compile-time or lint warnings that could block CI.
- Verify new code is wired into existing call chains.
- If a fix touches shared code, check callers for unintended side effects.
- Do NOT commit — pipeline handles commits.
