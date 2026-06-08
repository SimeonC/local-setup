---
name: autoplan
description: Create or refine autoplan plan chains. Creates atomic plan files linked as a chain plus a prompts file with domain-specific rules. Can also audit existing plans for inconsistencies, atomicity drift, prompts drift, chain integrity, and gaps.
user_invocable: true
user_invocable_name: /autoplan
---

Autoplan: $ARGUMENTS

## Dependencies

```sh
brew install fzf  # required by autoplan's adopt-current branch chooser
```

## Manual Verification

For flows that can't be auto-tested, create a companion `.md` file (e.g. `plan-name.manual.md`) with step-by-step instructions and set `manual_test: <path>` in the plan frontmatter. The harness runs it after `test_cmd` passes, opens the file's content as a pre-filled editor buffer; the tester closes it empty to pass, or types failure details to fail (failures are tagged `MANUAL TEST FAILURE` and re-enter `fix_test`). The instructions file is automatically deleted before the commit.

## Route
1. If $ARGUMENTS empty → AskUserQuestion: "Create new plan" or "Refine existing" (if Refine, also ask for the plan file path or folder).
2. If $ARGUMENTS resolves to a single `.md` file with autoplan frontmatter → Refine (single chain root).
3. If $ARGUMENTS resolves to a directory → Refine, treat as chain root folder; discover all `.md` plans inside, identify root(s) by absence of inbound `next:` links.
4. Else → Create.

## Dispatch
- Create path: read [references/create.md](references/create.md) and follow it.
- Refine path: read [references/refine.md](references/refine.md) and follow it.

Do NOT read the non-chosen sub-file.
