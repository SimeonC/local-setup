# Autoplan Gate Prompt

Read the plan file at $PLAN_FILE.

## Your task

Evaluate whether this plan is ready for fully automated implementation by the autoplan pipeline (gate → implement → test/fix → harden → verify/fix → commit). If any criteria below fail, edit the plan file directly to fix it. Write your verdict to $GATE_LOG when done.

## Evaluation criteria

Check ALL of the following. Every criterion must pass for READY.

### 1. Required frontmatter

The plan must have YAML frontmatter with these keys:
- `branch` — git branch name
- `test_cmd` — shell command to run tests
- `pr_title` — PR title string
- `prompts` — relative path to a prompts file that exists on disk

### 2. Concrete file paths

The Scope section must name **specific files, functions, or interfaces** to create or modify. Not vague areas like "refactor X" or "improve Y".

Pass: "Add `refreshToken()` to `src/auth/user-auth.service.ts`"
Fail: "Improve auth handling"

### 3. Testable acceptance criteria

The Verification section must list **automatable commands that pass or fail**. Not subjective checks like "looks correct" or "works as expected".

Pass: "`npm run test:ai -- --testPathPattern=auth`"
Fail: "Auth works as expected"

### 4. No ambiguous decisions

The plan must not leave architectural or design decisions to the implementing agent. No "choose between X or Y", "decide the best approach", or "consider whether to". All decisions must already be made.

Pass: "Use Redis for session caching with a 1-hour TTL"
Fail: "Choose an appropriate caching strategy"

### 5. Implementation specifics

Key function signatures, data structures, API shapes, or patterns must be defined — not left to the agent's judgment. The implementing agent should be a typist, not an architect.

Pass: "Add `POST /auth/refresh` returning `{ token: string, expiresIn: number }`"
Fail: "Add an endpoint for token refresh"

### 6. Atomicity (single session)

The plan must be completable in a single Claude session (~15-30 min of work). If it has internal ordering (step A must precede step B), it should be split into separate linked plans.

### 7. Prompts file completeness

If a `prompts` path is specified, the referenced file must exist and contain all 5 required sections:
- `## implement`
- `## fix_test`
- `## fix_verify`
- `## verify`
- `## harden`

Each fix section must include a concrete command for running a single failing test file.

## When a criterion fails

Edit the plan file (and prompts file if needed) directly to fix the issue. Use the codebase context to fill in specifics — file paths, function names, test commands, etc.

## Verdict

When done evaluating (and fixing if needed), write your verdict to $GATE_LOG:
- If ALL criteria pass: write `READY` on the first line.
- If you cannot fix a criterion (e.g. requires human decision): write `CANNOT_FIX` on the first line, followed by a numbered list of what remains unresolved.
