# Create: New Autoplan Chain

## Step 1: Gather Info

Use AskUserQuestion (up to 2 rounds, max 4 questions each).

**Round 1 — Identity:**
- Task name (becomes filename slug and PR title base)
- Branch name (e.g. `feat/auth-refactor`)
- Test command (e.g. `npm run test:ai`)
- PR title

**Round 2 — Domain rules:**
- Task description: 2-3 sentences summarising what needs to be built and why (becomes the `description` frontmatter field, shown in progress output)
- Domain-specific conventions for implementation (imports, patterns, file locations)
- Domain-specific verification checks (what to audit beyond "tests pass")
- Does this plan have flows that can't (or shouldn't) be auto-tested? If yes, create a companion `.md` file with step-by-step instructions and set `manual_test: <path>` in frontmatter. The harness runs it after `test_cmd` passes and deletes the file on completion.
- Any "never do" rules for fix steps (e.g. "never skip tests", "never weaken assertions")
- How do you run a single failing test file? (e.g. `npx nx run myapp:playwright -- <file>` or `npm run test:ai -- --testPathPattern=<file>`)

Also ask where to create the plan file (suggest current working directory).

Skip questions where `$ARGUMENTS` already provides the answer.

## Step 2: Generate Plan + Prompts Files

Create two files in the chosen directory:
- `<slug>-1.md` — the plan file (always name the first plan with `-1` suffix, even for single-plan chains)
- `<slug>-1-prompts.md` — the prompts file for plan 1

**ONE prompts file per plan.** Never share a single prompts file across multiple plans, even when the rules would be identical. Per-plan files force per-plan tailoring (Scope-specific guidance, focused fix/verify checks) and prevent the "generic prompts" laziness that produces out-of-scope drift.

See [plan-format.md](references/plan-format.md) and [prompts-format.md](references/prompts-format.md) for format specs.

The `description` frontmatter field must be a quoted single-line string of 2-3 sentences summarising what the plan does and why. For multi-plan chains, each plan's `description` should summarise only that plan's unit of work (not the whole chain).

Key points for prompts file:
- Populate all 5 sections with domain-specific rules from Step 1
- `fix_test` and `fix_verify` must follow the TDD red→green→commit pattern:

```markdown
## fix_test
Tests are failing. Output at $TEST_LOG.
Follow TDD: red → green → commit.
1. Read the test output to understand failures.
2. Run the failing tests to confirm: [HOW TO RUN SINGLE FAILING FILE]
3. Fix the root cause. Do NOT weaken assertions. Do NOT skip or remove tests.
4. Re-run tests to confirm they pass.
5. Commit fixes.

## fix_verify
Verify step found issues. Read $VERIFY_LOG.
Follow TDD: red → green → commit.
1. Read each issue.
2. Run the affected tests to confirm: [HOW TO RUN SINGLE FAILING FILE]
3. Fix the issues. Do NOT weaken, skip, or remove tests. Do NOT push or open a PR.
4. Re-run tests to confirm they pass.
5. Commit fixes.
```

Replace `[HOW TO RUN SINGLE FAILING FILE]` with the command gathered in Step 1 Round 2.

For multi-repo chains (each plan targets a different git repo), set `cwd:` to the sub-repo path relative to the chain's root directory, and set `create_branch: false` if the branch already exists locally in that repo. When `cwd:` is set, omit `cd <subdir> &&` from `test_cmd` and `verify_cmds`.

## Step 3: Evaluate Atomicity

For the plan (and each plan if split), check ALL of:

1. **Single session**: Could be implemented in ~one Claude session (~15-30 min of work)
2. **Concrete scope**: Names specific files, functions, or interfaces — NOT "refactor X" or "improve Y"
3. **Automatable verification**: Commands or `manual_test` that pass/fail — NOT "looks correct". `manual_test` satisfies this criterion for flows that aren't auto-testable.
4. **No internal ordering**: If step A must precede step B, they must be separate plans

If all pass, the plan is atomic. If any fail, proceed to Step 4.

## Step 4: Split if Needed

If a plan is not atomic, split into a linked chain:

- Name sub-plans: `<slug>-1.md`, `<slug>-2.md`, etc.
- **Each sub-plan gets its OWN prompts file**: `<slug>-1-prompts.md`, `<slug>-2-prompts.md`, etc. Start by copying the first plan's prompts file as a baseline for each new sub-plan, then tailor it to that sub-plan's specific Scope (focused fix/verify checks, scope-aware harden hints). Never point multiple plans at the same prompts file.
- Each sub-plan has own frontmatter:
  - Inherits `branch`, `test_cmd` from first plan (unless overridden); `pr_title` is optional
  - `prompts: ./<slug>-N-prompts.md` — points at THIS plan's dedicated prompts file
  - Each sub-plan (except last) has `next: ./<slug>-N+1.md`
- Each sub-plan has its own **Scope** and **Verification** scoped to just that unit's work

**Recurse:** Evaluate each sub-plan for atomicity. Split further if needed.

## Step 5: Validate Chain Integrity

- All `next:` files exist on disk
- No cycles (follow chain, detect if any file appears twice)
- Chain terminates (last plan has no `next:`)
- Report any broken links as errors and fix them

## Step 6: Validate Prompts Files

For EACH plan's referenced prompts file:
- File exists at the path in the plan's `prompts:` frontmatter.
- No two plans point to the same prompts file (one-prompts-per-plan invariant). If they do, copy and tailor — never share.
- All 5 sections present: `## implement`, `## fix_test`, `## fix_verify`, `## verify`, `## harden`
- Variables used correctly: `$PLAN_FILE` in implement, `$TEST_LOG` in fix_test, `$VERIFY_LOG` in verify and fix_verify
- Verify section contains specific structural checks tied to THIS plan's Scope — not generic "check correctness".
- Fix sections contain explicit "do NOT" rules.

Fix any issues found.

## Step 7: Final Readiness Table

Output a markdown table:

| Plan | Atomic? | Verification Specific? | Prompts Complete? | Status |
|------|---------|----------------------|-------------------|--------|
| `<slug>-1.md` | Yes/No | Yes/No | Yes/No | Ready / Needs Work |

## Step 8: Iterate

Work through each "Needs Work" item one at a time using AskUserQuestion to clarify if needed. Apply fixes. Re-evaluate. Repeat until all plans show **Ready**.
