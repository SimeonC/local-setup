## Fix-test phase
- Read $TEST_LOG. It may contain `# Auto Tests` and/or `# Manual Test Output` sections; treat any `MANUAL TEST FAILURE` banner as the authoritative failure description.
- Identify the root cause of each failure (missing implementation, wrong return value, wiring, environment) and fix the underlying code — not the test.
- If a fix touches shared code, check callers for unintended side effects.
- Do NOT modify manual_test instruction files.
