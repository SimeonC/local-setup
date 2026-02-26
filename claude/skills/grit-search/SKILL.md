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

## Recipes

### Find function/method calls
```bash
# All calls to a specific function
grit apply '`fetchData($...)`' --dry-run

# Method calls on a specific object
grit apply '`logger.$method($...)`' --dry-run

# Chained calls
grit apply '`$_.then($...).catch($...)`' --dry-run
```

### Find imports
```bash
# Imports from a specific package
grit apply '`import $_ from "lodash"`' --dry-run

# Named imports
grit apply '`import { $_ } from "react"`' --dry-run

# Require calls
grit apply '`require("express")`' --dry-run
```

### Find definitions
```bash
# Function definitions
grit apply '`function $name($...) { $_ }`' --dry-run

# Arrow functions assigned to const
grit apply '`const $name = ($...) => $_`' --dry-run

# Class definitions
grit apply '`class $name { $_ }`' --dry-run

# Type/interface definitions
grit apply '`interface $name { $_ }`' --dry-run
```

### Find usages in context
```bash
# Find usage inside async functions
grit apply '`await $fn($...)`' --dry-run

# Find usage inside try/catch
grit apply '`try { $body } catch($_) { $_ }` where { $body <: contains `$target($...)` }' --dry-run

# Find usage inside specific function
grit apply '`function handleSubmit($...) { $body }` where { $body <: contains `validate($...)` }' --dry-run
```

### Find patterns with conditions
```bash
# Find variables matching a regex
grit apply '`const $name = $_` where { $name <: r"^use[A-Z]" }' --dry-run

# Find calls with specific argument count
grit apply '`$fn($a, $b, $c, $...rest)` where { $fn <: `createServer` }' --dry-run
```

### Find by file
```bash
# Search only test files
grit apply '`describe($_, $...)`' --dry-run -- '**/*.test.*'

# Search only in src/
grit apply '`console.log($...)`' --dry-run -- src/
```

## Tips

- **Search-only patterns** — just write the match side, no `=>` rewrite needed
- **Use `$...`** for "any arguments" — `$fn($...)` matches calls with any number of args
- **Use `$_`** for "don't care" — when you need to fill a syntax position but don't care about the value
- **Quote the pattern** in the shell — use single quotes to avoid shell interpolation of `$`
- **Start broad, then narrow** — begin with a simple pattern, add `where` clauses to filter
- If you want to then **refactor** the found code, use `/grit-refactor`
