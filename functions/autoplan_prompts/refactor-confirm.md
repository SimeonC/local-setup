## Refactor confirmation
Before applying any **non-mechanical** refactor or fix, call `AskUserQuestion` to confirm the change with the user. Apply only after approval.

- **Mechanical** (apply without asking): rename a symbol consistently, move a file/import path that the plan names, fix an obvious typo, delete clearly dead code introduced by this diff, add a missing test for code in the diff.
- **Non-mechanical** (must confirm first): extract a helper/abstraction, restructure an existing function, change a public signature, change error-handling shape, swap a library or pattern, anything that materially changes how the code is organized rather than what it does.

When in doubt, treat it as non-mechanical and ask.
