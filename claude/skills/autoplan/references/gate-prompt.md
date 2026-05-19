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

### 7. Prompts file shape

If a `prompts` path is specified, the referenced file must exist. Sections (`## implement`, `## fix_test`, `## fix_verify`, `## fix_verify_cmd`, `## verify`, `## harden`) are optional — missing sections fall back to the harness's process-rule-only prompt. The fix sections SHOULD include a concrete single-failing-file run command for this domain.

**Domain context only — process rules are harness-owned.** If any section contains process-rule language, flag it and remove it. The following are harness-owned and must NOT appear in any prompts-file section:

- TDD step lists (red/green/commit ordering).
- "Do NOT commit / push / stage / stash / reset / revert / ...".
- Plan-scope discipline restatements ("only implement Scope", "ignore `next:`").
- Sentinel-file write contracts (`ALL_GOOD` / `ISSUES_FOUND`).
- "Audit-only" / "Do NOT edit files" stance for `## verify`.
- Refactor-confirmation rules.
- Test integrity rules (`.only`/`.skip`/TODO bans, "every public function must have a test").
- "Do NOT run lint/typecheck/build/full test suites".

The prompts file's `## harden` section must NOT contain literal shell commands or test-runner invocations (e.g. `npm run lint`, `mix test`, `nx run …`). Those are deterministic checks that belong in the plan's `verify_cmds:` frontmatter list (executed by the harness, not by Claude). If found, move them to the plan's `verify_cmds:`.

## When a criterion fails

Edit the plan file (and prompts file if needed) directly to fix the issue. Use the codebase context to fill in specifics — file paths, function names, test commands, etc.

## Rules

- Do NOT stage, commit, push, or open a PR. A later pipeline step handles commits.

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
