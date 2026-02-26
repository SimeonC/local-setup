---
name: grit-refactor
description: Mass refactor using GritQL patterns. Use when the user wants to do large-scale code transformations, rename patterns across files, migrate APIs, or apply structural find-and-replace.
disable-model-invocation: false
argument-hint: [description of the refactor to perform]
---

# Grit Mass Refactor

Apply a mass refactor across the codebase using GritQL. The user will describe the refactor in `$ARGUMENTS`.

## Workflow

1. **Understand the refactor** — parse `$ARGUMENTS` to determine what transformation is needed
2. **Write a GritQL pattern** — create a `.grit/patterns/<pattern_name>.md` file with the pattern and test cases
3. **Test the pattern** — run `grit patterns test --filter=<pattern_name>`
4. **Dry run** — run `grit apply <pattern_name> --dry-run` to preview changes
5. **Show the user** the dry-run output and ask for confirmation
6. **Handle uncommitted changes** — `grit apply` will fail if there are uncommitted changes. Before using `--force`:
   - Run `git status` to check what the uncommitted changes are
   - If there are meaningful changes, ask the user to commit first (so there's a safe rollback point)
   - Only use `--force` after confirming the uncommitted changes are understood
7. **Apply** — run `grit apply <pattern_name>` (or `--force` if step 6 cleared it)
8. **Verify** — run linter/typecheck to confirm no breakage
9. **Clean up** — for small/one-off refactors, delete the pattern file after applying (`rm .grit/patterns/<pattern_name>.md`). Keep pattern files that are reusable, enforced via `grit check`, or represent significant refactors (they help reviewers understand the transformation in PRs).
10. **Show summary** — `git diff --stat` to summarize changes

## GritQL Syntax

See [gritql](../gritql/SKILL.md) for the complete GritQL syntax, built-in functions, and pattern-writing guide.

## Pattern File Format

Patterns live in `.grit/patterns/<pattern_name>.md`. The filename (minus `.md`) becomes the pattern name.

```markdown
---
level: info
tags: [refactor]
---
# Pattern Title

Brief description of what this pattern does.

\`\`\`grit
// GritQL body goes here
`old_code($var)` => `new_code($var)`
\`\`\`

## Test: description of positive case

\`\`\`typescript
// Input code
old_code("hello");
\`\`\`

\`\`\`typescript
// Expected output
new_code("hello");
\`\`\`

## Test: negative case (should not match)

\`\`\`typescript
// This code should be unchanged — single block with no expected output = negative test
unrelated_code("hello");
\`\`\`
```

### Test case rules
- **Single code block** = negative test (pattern should NOT match this code)
- **Two code blocks** = first is input, second is expected output (positive test)
- Run tests: `grit patterns test --filter=<pattern_name>`

## CLI Quick Reference

| Command | Purpose |
|---------|---------|
| `grit apply <pattern> --dry-run` | Preview changes without applying |
| `grit apply <pattern>` | Apply the pattern |
| `grit apply <pattern> --force` | Apply even with uncommitted changes |
| `grit apply <pattern> --language <lang>` | Specify target language |
| `grit apply <pattern> -m <N>` | Limit to N matches |
| `grit patterns test --filter=<name>` | Run tests for a pattern |
| `grit patterns test --update` | Update expected test outputs |
| `grit check` | Check for pattern violations |
| `grit check --fix` | Auto-fix violations |
| `grit list` | List available patterns |
| `grit init` | Install grit modules |

## Important Notes

- Always create a `.grit/` directory if it doesn't exist: `mkdir -p .grit/patterns`
- Always write tests before applying — catch edge cases early
- Always dry-run before applying
- Always ask the user before applying changes
- Patterns in `.grit/patterns/` are auto-discovered — no need to register them
- Use `// grit-ignore pattern_name: reason` to suppress matches inline
