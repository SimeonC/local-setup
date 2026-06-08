# Refine: Audit Existing Autoplan Chain

## Step 1: Discover Chain

- If input is a file: start from it, follow `next:` links to build the full chain.
- If input is a folder: glob `*.md` files, identify root(s) as plans not referenced by any other plan's `next:`. Follow each chain from each root.
- Report multiple roots or orphaned plans (plans not reachable from any root and not a root themselves) as issues.

## Step 2: Frontmatter Completeness

For each plan, check all required frontmatter fields are present and non-empty:
- `description` — must be a quoted single-line string (2-3 sentences). If missing, generate one from the plan's Context + Scope sections and add it.
- `commit_msg` — must be a quoted single-line gitmoji message. If missing, generate one from the plan's title/Context/Scope and add it. Use gitmoji conventions: `✨` new feature, `🐛` bug fix, `♻️` refactor, `🔧` config/tooling, `📝` docs, `✅` tests, `🚀` performance, `🔥` remove, `💄` UI/style, `🔒` security.
- `test_cmd` (or `manual_test`), `prompts` — flag any missing as errors.
- `branch:` — optional; omitting or `<current>` = adopt-current mode. Flag any `create_branch:` key as deprecated and remove it.
- `cwd:` — if set, verify the path exists relative to the run root. If `test_cmd` or `verify_cmds` contain a `cd <subdir> &&` prefix that matches `cwd:`, flag as redundant and remove.

## Step 3: Chain Integrity

Apply existing chain integrity checks:
- All `next:` files exist on disk
- No cycles (detect if any file appears twice in chain traversal)
- Chain terminates (last plan has no `next:`)
- Report any broken links as errors

## Step 4: Per-Plan Atomicity Re-check

For each plan in the chain, re-evaluate atomicity against all six criteria:
1. **Single session**: Could be implemented in ~one Claude session (~15-30 min)
2. **Concrete scope**: Names specific files, functions, or interfaces — not vague
3. **Automatable verification**: Commands that pass/fail — not subjective
4. **No internal ordering**: Steps within a plan must not depend on each other's order
5. **No ambiguous decisions**: Must not leave architectural or design choices to the implementing agent — no "choose between X or Y", "decide the best approach", or "consider whether to". All decisions must already be made.
6. **Implementation specifics**: Key function signatures, data structures, API shapes, or patterns must be defined — not left to the agent's judgment. The implementing agent should be a typist, not an architect.

## Step 5: Cross-Plan Inconsistencies

Check for:
- Scope overlap between plans (same file/function modified by multiple plans)
- Duplicate work (same task described in two plans)
- Contradictory conventions (different naming, patterns, file locations between plans)
- Orphaned file references (plan mentions a file/function that no earlier plan creates)

## Step 6: Prompts Drift

For each plan's referenced `prompts` file:
- **One prompts file per plan** — each plan must point to its OWN dedicated prompts file. If two plans share a `prompts:` path, flag as a violation and split: copy the shared file to `<slug>-N-prompts.md` per plan, tailor each, update frontmatter.
- Sections present should be a subset of: `## implement`, `## fix_test`, `## fix_verify`, `## fix_verify_cmd`, `## verify`, `## harden`. Missing sections are OK — the harness still runs the phase with only the system-prompt process rules.
- **Domain context only — flag any process-rule language.** Process rules are harness-owned and must NOT appear in any section. Flag and remove if found:
  - TDD step lists (red/green/commit ordering).
  - "Do NOT commit / push / stage / stash / reset / revert / ...".
  - Plan-scope discipline restatements ("only implement Scope", "ignore `next:`", "spec is only $PLAN_FILE").
  - Sentinel-file write contracts (`ALL_GOOD` / `ISSUES_FOUND`).
  - "Audit-only" / "Do NOT edit files" stance for `## verify`.
  - Refactor-confirmation rules.
  - Test integrity rules (`.only`/`.skip`/TODO bans, "every public function must have a test").
  - "Do NOT run lint/typecheck/build/full test suites".
- Variables used in domain notes are valid (`$PLAN_FILE`, `$TEST_LOG`, `$VERIFY_LOG`, `$VERIFY_CMD_LOG`, `$BRANCH`, `$TEST_CMD`).
- Test-run commands referenced in domain context: quick grep in the repo to confirm `package.json` script / nx project still exists.
- Domain rules reference files that still exist on disk.
- `## harden` section MUST NOT contain literal shell commands or test-runner invocations (e.g. `npm run lint`, `mix test`, `nx run …`). Those are deterministic checks that belong in the plan's `verify_cmds:` frontmatter list. If found, flag the issue and move the commands to frontmatter.

## Step 7: Gap Detection

Enumerate likely missing work across these categories:
- Database migrations or schema changes
- Config / environment variable changes
- Documentation updates
- TypeScript types or interfaces for new code paths
- Tests for new code paths not yet covered
- Rollback or cleanup procedures
- Feature-flag lifecycle (creation, removal)
- Telemetry / logging / monitoring

For each gap found, it must be resolved as one of:
- **Covered**: reference which plan + section already handles it
- **Ignored**: add to the plan's `## Out of Scope` with explicit reason
- **Deferred**: create a new linked plan stub or note in `## Out of Scope` with a pointer to a follow-up

## Step 8: Report and Resolve Issues

Output a findings table:

| # | Plan | Category | Issue | Severity |
|---|------|----------|-------|----------|
| 1 | slug-1.md | Atomicity | ... | High/Med/Low |

Then use AskUserQuestion in batches of ≤4 questions, offering **Fix / Ignore / Defer** per issue.
Apply the chosen action:
- Fix: edit the plan file directly
- Ignore: add entry to plan's `## Out of Scope`
- Defer: create a follow-up plan stub file and link it, or add to `## Out of Scope` with pointer

## Step 9: Re-run Until Clean

Re-run all checks (Steps 2–7) after applying fixes. Repeat until no issues remain.

## Step 10: Final Readiness Table

| Plan | Chain OK? | Atomic? | Prompts OK? | Gaps Resolved? | Status |
|------|-----------|---------|-------------|----------------|--------|
| slug-1.md | Yes/No | Yes/No | Yes/No | Yes/No | Ready / Needs Work |
