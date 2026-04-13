---
name: grit-search
description: Structural code search using GritQL patterns. Use when the user wants to find code occurrences, locate usages, search for patterns, or find all instances of something across a codebase.
disable-model-invocation: false
argument-hint: [description of what to find]
---

# Grit Code Search

Find code occurrences across the codebase using GritQL structural search. The user will describe what to find in `$ARGUMENTS`.

## Workflow

1. **Understand the search** — parse `$ARGUMENTS` to determine what code to find
2. **Write a GritQL pattern** — create an inline pattern (no rewrite, just the match side)
3. **Run the search** — `grit apply '<pattern>' --dry-run`
4. **Present results** — show matches to the user
5. **Refine if needed** — adjust pattern based on results (too many/few matches, wrong matches)

## GritQL Syntax

See [gritql](../gritql/SKILL.md) for full GritQL pattern syntax, operators, and built-in functions.

## Search Commands

```bash
# Basic search — shows matched files and locations
grit apply '<pattern>' --dry-run

# Structured output — machine-readable results
grit apply '<pattern>' --dry-run --jsonl

# Limit results
grit apply '<pattern>' --dry-run -m 20

# Search specific language
grit apply '<pattern>' --dry-run --language typescript

# Search specific paths
grit apply '<pattern>' --dry-run -- src/
```

## Quick Examples

```bash
# All calls to a specific function
grit apply '`fetchData($...)`' --dry-run

# Named imports from a package
grit apply '`import { $_ } from "react"`' --dry-run

# Class definitions
grit apply '`class $name { $_ }`' --dry-run
```

See [../gritql/references/recipes.md](../gritql/references/recipes.md) for more patterns grouped by intent.

## Tips

- **Search-only patterns** — just write the match side, no `=>` rewrite needed
- **Use `$...`** for "any arguments" — `$fn($...)` matches calls with any number of args
- **Use `$_`** for "don't care" — when you need to fill a syntax position but don't care about the value
- **Quote the pattern** in the shell — use single quotes to avoid shell interpolation of `$`
- **Start broad, then narrow** — begin with a simple pattern, add `where` clauses to filter
- If you want to then **refactor** the found code, use `/grit-refactor`
