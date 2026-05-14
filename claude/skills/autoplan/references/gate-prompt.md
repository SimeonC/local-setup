# Autoplan Gate Prompt

Read the plan file at $PLAN_FILE.

## Your task

Evaluate whether this plan is ready for fully automated implementation by the autoplan pipeline (gate → implement → test/fix → harden → verify/fix → commit). If any criteria below fail, edit the plan file directly to fix it. Write your verdict to two sentinel files when done (see "Verdict" below).

## Evaluation criteria

Check ALL of the following. Every criterion must pass for READY.

### 1. Required frontmatter

The plan must have YAML frontmatter with these keys:
- `branch` — git branch name
- `test_cmd` and/or `manual_test` — at least one must be present:
  - `test_cmd` — shell command to run automated tests
  - `manual_test` — path to a manual test instruction file
- `pr_title` — optional, PR title string; omit to skip PR creation
- `prompts` — relative path to a prompts file that exists on disk

### 2. Concrete file paths

The Scope section must name **specific files, functions, or interfaces** to create or modify. Not vague areas like "refactor X" or "improve Y".

Pass: "Add `refreshToken()` to `src/auth/user-auth.service.ts`"
Fail: "Improve auth handling"

### 3. Testable acceptance criteria

The plan must have verification — either in the Verification section (automatable commands) or via `test_cmd`/`manual_test` in frontmatter. Not subjective checks like "looks correct" or "works as expected".

Pass: `test_cmd: "npm run test:ai -- --testPathPattern=auth"` or `manual_test: ./auth-refresh.manual.md`
Fail: "Auth works as expected" or neither `test_cmd` nor `manual_test` present with no Verification section

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

When done evaluating (and fixing if needed), write your verdict to TWO files. Both are required.

### 1. `$GATE_RESULT` — machine-readable, exactly one line

Write exactly one of:
- `READY` — all criteria pass.
- `CANNOT_FIX` — one or more criteria failed and require human decisions.

No prose, no list, no trailing content. Just the single word on a single line.

### 2. `$GATE_SUMMARY` — human-readable summary

Write a short summary of what you evaluated and what (if anything) you edited in the plan or prompts files. Keep it concise — a few bullets or a short paragraph.

If the result is `CANNOT_FIX`, include a numbered list of the unresolved items (what needs human input and why).
