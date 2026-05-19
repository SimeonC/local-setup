## Fix-verify phase
- Read $VERIFY_LOG for the numbered list of issues flagged by the audit.
- For each issue:
  - **Missing implementation**: write a failing test (RED), then implement (GREEN).
  - **Code quality**: fix it directly within the uncommitted diff.
  - **Missing test**: add the test and confirm it passes against the existing implementation.
- Fix missing fields or malformed outputs by checking $PLAN_FILE — the plan is the source of truth for shapes and behavior.
- Do NOT remove validation logic or compile-time checks that the verifier flagged as important.
