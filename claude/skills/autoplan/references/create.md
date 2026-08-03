# Create: New Autoplan Chain

## Step 1: Gather Info

Use AskUserQuestion (up to 2 rounds, max 4 questions each).

**Round 1 — Identity:**
- Task name (becomes filename slug and PR title base)
- Branch name (e.g. `feat/auth-refactor`)
- Test command(s) for `test_cmds` (e.g. `npm run test:ai`)
- PR title

**Round 2 — Domain rules:**
- Task description: 2-3 sentences summarising what needs to be built and why (becomes the `description` frontmatter field, shown in progress output)
- Domain-specific conventions for implementation (imports, patterns, file locations)
- Domain-specific verification checks (what to audit beyond "tests pass")
- Does this plan have flows that can't (or shouldn't) be auto-tested? If yes, create a companion `.md` file with step-by-step instructions and set `manual_test: <path>` in frontmatter. The harness runs it after `test_cmds` pass and deletes the file on completion.
- Is UI direction worth settling interactively before implementing? If yes, set `prototype: true` in frontmatter and populate the `## prototype` section of the prompts file with project-specific UI conventions (design tokens, existing components to match, color/spacing conventions, Figma link if available).
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

The `commit_msg` frontmatter field must be a quoted single-line gitmoji commit message derived from this plan's title and Scope — e.g. `"✨ Add token refresh endpoint"`, `"🐛 Fix race condition in session cleanup"`. Use these conventions: `✨` new feature, `🐛` bug fix, `♻️` refactor, `🔧` config/tooling, `📝` docs, `✅` tests, `🚀` performance, `🔥` remove code/files, `💄` UI/style, `🔒` security. Keep it under 72 characters. Each plan in a chain gets its own `commit_msg` scoped to that plan's work.

Key points for prompts file:
- Populate all 5 sections with domain-specific rules from Step 1
- Prompts sections are **domain context only** — process rules (TDD ordering, "do NOT commit", sentinel write contracts, test integrity, scope discipline) are harness-injected and must NOT be restated. See [prompts-format.md](references/prompts-format.md) for the full forbidden-language list.
- `fix_test` and `fix_verify` must contain the single-failing-file run command and any domain-specific notes (log paths, helper locations). Replace `[HOW TO RUN SINGLE FAILING FILE]` with the command gathered in Step 1 Round 2:

```markdown
## fix_test
Single failing file: [HOW TO RUN SINGLE FAILING FILE]
Test output aggregated at $TEST_LOG (sections: `# Auto Tests`, `# Manual Test Output`).

## fix_verify
Single failing file: [HOW TO RUN SINGLE FAILING FILE]
Verify findings at $VERIFY_LOG.
```

For multi-repo chains (each plan targets a different git repo), set `cwd:` to the sub-repo path relative to the chain's root directory. Use `branch: <name>` to ensure/create a specific branch in that repo, `branch: <current>` to adopt the current checkout silently, or omit `branch:` to adopt with an interactive chooser. When `cwd:` is set, omit `cd <subdir> &&` from `test_cmds` entries.

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
  - Inherits `branch`, `test_cmds` from first plan (unless overridden); `pr_title` is optional
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
