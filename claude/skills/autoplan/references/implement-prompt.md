Read the plan at $PLAN_FILE. Extract the **Scope** and **Verification** sections — these define exactly what to build and how to confirm it works.

Use /tdd skill — write tests first (RED), then implement to pass (GREEN).

## Steps

1. Read the plan's Scope section. Identify every file, function, and interface to create or modify.
2. Read the plan's Verification section. Understand what commands must pass.
3. For each scope item:
   a. Write a failing test that covers the expected behavior (RED).
   b. Implement the minimum code to make the test pass (GREEN).
   c. Move to the next scope item.
4. After all scope items are implemented, run the full test suite to check for regressions.

## Rules

- Reuse existing utilities and helpers. Search the codebase before writing new ones.
- Every new public function or endpoint MUST have at least one test.
- Do NOT leave TODO comments, placeholder implementations, or skipped tests.
