---
name: prepare-autoplan
description: Prepare autoplan-ready plan files from a task description. Creates atomic plan files linked as a chain, plus a prompts file with domain-specific rules. Replaces /create-plan, /refine-plan, /split-plan. Use when preparing work for autoplan execution.
user_invocable: true
user_invocable_name: /prepare-autoplan
---

Prepare autoplan-ready plan files: $ARGUMENTS

## Step 1: Gather Info

Use AskUserQuestion (up to 2 rounds, max 4 questions each).

**Round 1 — Identity:**
- Task name (becomes filename slug and PR title base)
- Branch name (e.g. `feat/auth-refactor`)
- Test command (e.g. `npm run test:ai`)
- PR title

**Round 2 — Domain rules:**
- Task description (what needs to be built, high level)
- Domain-specific conventions for implementation (imports, patterns, file locations)
- Domain-specific verification checks (what to audit beyond "tests pass")
- Any "never do" rules for fix steps (e.g. "never skip tests", "never weaken assertions")

Also ask where to create the plan file (suggest current working directory).

Skip questions where `$ARGUMENTS` already provides the answer.

## Step 2: Generate Plan + Prompts Files

Create two files in the chosen directory:
- `<slug>.md` — the plan file
- `<slug>-prompts.md` — the prompts file

### Plan file format

```markdown
---
branch: feat/...           # required
test_cmd: npm run test:ai   # required
pr_title: "..."             # required
prompts: ./<slug>-prompts.md # required
next: ./<slug>-2.md         # optional, only if chain exists
---

# Title

## Context
Why this work is needed.

## Scope
- Concrete list of what to implement (specific files, functions, interfaces)
- NOT vague ("refactor X", "improve Y")

## Verification
- Specific, automatable checks (commands that pass/fail)
- NOT subjective ("looks correct")
```

### Prompts file format

```markdown
# Prompts: <task name>

## implement
<domain-specific implementation instructions>
Read the plan at $PLAN_FILE. Use /tdd skill.
Rules:
- [domain conventions from Step 1]

## fix_test
<domain-specific test fix instructions>
Tests failing. Output at $TEST_LOG. Diagnose and fix.
Rules:
- Do NOT weaken assertions or skip tests
- [domain-specific rules from Step 1]

## fix_verify
<domain-specific verify fix instructions>
Verify step flagged issues in $VERIFY_LOG. Fix them.
Rules:
- Do NOT weaken/skip tests. Do NOT push.
- [domain-specific rules from Step 1]

## verify
<domain-specific audit checklist>
Audit-only. Do NOT edit files, commit, push, or open a PR.
Check:
1. [specific structural check]
2. [specific structural check]
...
Write ALL_GOOD to $VERIFY_LOG if all pass.
Write ISSUES_FOUND on line 1, numbered issues below, if any fail.

## harden
<domain-specific hardening guidance>
Review uncommitted changes. Fix: duplication, SOLID violations, dead code, missing coverage.
Re-run tests after each change. Context: $PLAN_FILE.
```

**Variables available in prompts:** `$PLAN_FILE`, `$TEST_LOG`, `$VERIFY_LOG`, `$BRANCH`

Populate all 5 sections with the domain-specific rules gathered in Step 1.

## Step 3: Evaluate Atomicity

For the plan (and each plan if split), check ALL of:

1. **Single session**: Could be implemented in ~one Claude session (~15-30 min of work)
2. **Concrete scope**: Names specific files, functions, or interfaces — NOT "refactor X" or "improve Y"
3. **Automatable verification**: Commands that pass/fail — NOT "looks correct"
4. **No internal ordering**: If step A must precede step B, they must be separate plans

If all pass, the plan is atomic. If any fail, proceed to Step 4.

## Step 4: Split if Needed

If a plan is not atomic, split into a linked chain:

- Name sub-plans: `<slug>-1.md`, `<slug>-2.md`, etc.
- Each sub-plan has own frontmatter:
  - Inherits `branch`, `test_cmd`, `pr_title`, `prompts` from first plan (unless overridden)
  - Each sub-plan (except last) has `next: ./<slug>-N+1.md`
- Each sub-plan has its own **Scope** and **Verification** scoped to just that unit's work

**Recurse:** Evaluate each sub-plan for atomicity. Split further if needed.

## Step 5: Validate Chain Integrity

- All `next:` files exist on disk
- No cycles (follow chain, detect if any file appears twice)
- Chain terminates (last plan has no `next:`)
- Report any broken links as errors and fix them

## Step 6: Validate Prompts File

Check:
- All 5 sections present: `## implement`, `## fix_test`, `## fix_verify`, `## verify`, `## harden`
- Variables used correctly: `$PLAN_FILE` in implement, `$TEST_LOG` in fix_test, `$VERIFY_LOG` in verify and fix_verify
- Verify section contains specific structural checks, not generic "check correctness"
- Fix sections contain explicit "do NOT" rules

Fix any issues found.

## Step 7: Final Readiness Table

Output a markdown table:

| Plan | Atomic? | Verification Specific? | Prompts Complete? | Status |
|------|---------|----------------------|-------------------|--------|
| `<slug>.md` | Yes/No | Yes/No | Yes/No | Ready / Needs Work |

## Step 8: Iterate

Work through each "Needs Work" item one at a time using AskUserQuestion to clarify if needed. Apply fixes. Re-evaluate. Repeat until all plans show **Ready**.
