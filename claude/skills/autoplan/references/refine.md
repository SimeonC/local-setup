# Refine: Audit Existing Autoplan Chain

## Step 1: Discover Chain

- If input is a file: start from it, follow `next:` links to build the full chain.
- If input is a folder: glob `*.md` files, identify root(s) as plans not referenced by any other plan's `next:`. Follow each chain from each root.
- Report multiple roots or orphaned plans (plans not reachable from any root and not a root themselves) as issues.

## Step 2: Chain Integrity

Apply existing chain integrity checks:
- All `next:` files exist on disk
- No cycles (detect if any file appears twice in chain traversal)
- Chain terminates (last plan has no `next:`)
- Report any broken links as errors

## Step 3: Per-Plan Atomicity Re-check

For each plan in the chain, re-evaluate atomicity against all four criteria:
1. **Single session**: Could be implemented in ~one Claude session (~15-30 min)
2. **Concrete scope**: Names specific files, functions, or interfaces — not vague
3. **Automatable verification**: Commands that pass/fail — not subjective
4. **No internal ordering**: Steps within a plan must not depend on each other's order

## Step 4: Cross-Plan Inconsistencies

Check for:
- Scope overlap between plans (same file/function modified by multiple plans)
- Duplicate work (same task described in two plans)
- Contradictory conventions (different naming, patterns, file locations between plans)
- Orphaned file references (plan mentions a file/function that no earlier plan creates)

## Step 5: Prompts Drift

For each plan's referenced `prompts` file:
- All 5 sections present: `## implement`, `## fix_test`, `## fix_verify`, `## verify`, `## harden`
- Variables used correctly: `$PLAN_FILE` in implement, `$TEST_LOG` in fix_test, `$VERIFY_LOG` in verify/fix_verify
- Test-run commands: quick grep in the repo to confirm `package.json` script / nx project still exists
- Domain rules reference files that still exist on disk

## Step 6: Gap Detection

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

## Step 7: Report and Resolve Issues

Output a findings table:

| # | Plan | Category | Issue | Severity |
|---|------|----------|-------|----------|
| 1 | slug.md | Atomicity | ... | High/Med/Low |

Then use AskUserQuestion in batches of ≤4 questions, offering **Fix / Ignore / Defer** per issue.
Apply the chosen action:
- Fix: edit the plan file directly
- Ignore: add entry to plan's `## Out of Scope`
- Defer: create a follow-up plan stub file and link it, or add to `## Out of Scope` with pointer

## Step 8: Re-run Until Clean

Re-run all checks (Steps 2–6) after applying fixes. Repeat until no issues remain.

## Step 9: Final Readiness Table

| Plan | Chain OK? | Atomic? | Prompts OK? | Gaps Resolved? | Status |
|------|-----------|---------|-------------|----------------|--------|
| slug.md | Yes/No | Yes/No | Yes/No | Yes/No | Ready / Needs Work |
