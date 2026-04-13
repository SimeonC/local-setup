---
name: gritql
description: GritQL pattern syntax reference. Use when the user needs help writing GritQL patterns, asks about GritQL syntax, or wants to understand how to use GritQL operators.
disable-model-invocation: false
argument-hint: [syntax question or pattern to help write]
---

# GritQL Language Reference

GritQL is a declarative query language for structural code search and transformation. It works on syntax trees (not strings), so it matches semantically equivalent code regardless of formatting.

## Pattern Types

### Code Snippets (most common)
Wrap target-language code in backticks. Use `$metavariables` for holes:

```grit
`console.log($message)`
```

Matches any `console.log` call regardless of argument value, quote style, or whitespace.

**Important:** Code inside backticks must be **valid syntax** in the target language. You cannot put arbitrary fragments in backticks — they must parse. For arbitrary strings, use string literals or regex instead.

### Metavariables
- `$name` — Named capture (binds to a value; same name = same value constraint)
- `$_` — Anonymous wildcard (matches anything, no binding)
- `$...` — Spread (matches 0 or more nodes in argument lists, arrays, object fields)

```grit
// $a must be the same in both positions
`$a + $a`

// Matches any function with any args
`function $name($...) { $body }`
```

### AST Node Patterns
Match syntax tree nodes directly by type with named fields. Use when code snippets can't express what you need:

```grit
call_expression(callee=$callee, arguments=$args)
```

When to use AST nodes vs code snippets:
- **Code snippets** — when you can write valid target-language code with holes
- **AST nodes** — when the pattern isn't expressible as valid syntax (e.g., matching a bare expression kind, combining fields that aren't valid together in source)

### Regular Expressions
Prefix with `r"`:

```grit
$name <: r"test.*"
// With capture groups:
$filename <: r"(.*)\.test\.ts$"($base_name)
```

### String Literals
Match exact strings with quotes:

```grit
$message <: "hello world"
```

## Rewrites

Transform matched code with `=>`:

```grit
`console.log($msg)` => `logger.info($msg)`
```

Delete code by rewriting to `.` (empty pattern):

```grit
`console.log($msg)` => .
```

## Where Clauses

Add conditions to filter matches:

```grit
`console.log($msg)` => `logger.info($msg)` where {
  $msg <: `"user-facing: $_"`
}
```

### Operators in where clauses

| Operator | Meaning |
|----------|---------|
| `<:` | Matches against (left matches right pattern) |
| `=` | Assign a value to a metavariable |
| `+=` | Accumulate/append to a string or list |

## Tree Traversal (contains / within / after)

This is the most important section — tree traversal is how you compose patterns.

### `contains` — search downward
Match if the target node contains a descendant matching the pattern:

```grit
// Find files that contain console.log
file($body) where {
  $body <: contains `console.log($_)`
}

// Find functions that contain a return statement
`function $name($...) { $body }` where {
  $body <: contains `return $_`
}
```

### `within` — search upward
Match if the target node is inside an ancestor matching the pattern:

```grit
// Match console.log only inside catch blocks
`console.log($msg)` where {
  $msg <: within `catch($_) { $_ }`
}
```

### `after` — sequential position
Match a pattern that appears after another:

```grit
after `import $_ from $_`
```

### Combining traversals
```grit
// Find console.log inside async functions but not in catch blocks
`console.log($msg)` where {
  $msg <: within `async function $name($...) { $_ }`,
  not { $msg <: within `catch($_) { $_ }` }
}
```

## Scope and Bubble

When using `contains` with rewrites, use `bubble` to isolate variable scope. Without bubble, metavariables from the inner pattern leak into the outer scope and cause conflicts.

```grit
// Without bubble, $body would conflict with outer scope
file($body) where {
  $body <: contains bubble {
    `console.log($msg)` => `logger.info($msg)`
  }
}
```

Pierce the bubble to share specific variables between inner and outer scope:

```grit
$body <: contains bubble($shared_var) {
  `$shared_var.log($msg)` => `$shared_var.info($msg)`
}
```

**Pitfall:** Forgetting `bubble` when using `contains` with rewrites is the #1 cause of unexpected behavior. Always use `bubble` when your `contains` block has a rewrite (`=>`).

## Compound Operators

```grit
// Match either pattern
or {
  `console.log($msg)`,
  `console.warn($msg)`,
  `console.error($msg)`
} => `logger.info($msg)`

// All conditions must hold
and {
  `$fn($args)`,
  $fn <: r"deprecated.*"
}

// Negate
not { `console.log($_)` }

// Optional match (doesn't fail if no match)
maybe { `console.log($msg)` => `logger.info($msg)` }
```

## Collections

### Lists
```grit
$list = [1, 2, 3]
$first = $list[0]
$last = $list[-1]
```

### Maps
```grit
$map = { key: "value" }
$val = $map.key
```

### Some (at least one element matches)
```grit
$statements <: some `console.log($_)`
```

## Accumulation Pattern

Build up values across matches:

```grit
$imports = "",
$body <: some bubble($imports) `import $name from $_` where {
  $imports += $name
}
```

## Built-in Functions

See [references/functions.md](references/functions.md) for the full built-in functions table.

## Custom Functions

### GritQL functions
```grit
function add_prefix($name) {
  $result = `prefix_$name`,
  return $result
}
```

### JavaScript functions
```grit
function to_snake_case($name) js {
  const text = $name.text;
  return text.replace(/([A-Z])/g, '_$1').toLowerCase();
}
```

JS functions run in a WASM sandbox — no filesystem or network access. Access metavariables via `$var.text`.

## Special Metavariables

| Variable | Meaning |
|----------|---------|
| `$program` | The entire file contents |
| `$filename` | Path of the current file |
| `$new_files` | Accumulate to create new files |

### Creating new files
```grit
$new_files += file(name="new_file.ts", body=$content)
```

## Sequential Patterns

Apply multiple steps in order (top-level only):

```grit
sequential {
  // Step 1: rename imports
  contains `import { $old } from "old-pkg"` => `import { $old } from "new-pkg"`,
  // Step 2: rename usages
  contains `old_function($args)` => `new_function($args)`
}
```

**Note:** Sequential steps are NOT auto-wrapped — include `contains` yourself.

## Multifile Patterns

Match across files using `file()`:

```grit
multifile {
  $file1 <: file(name="config.ts", body=contains `export const $name = $_`),
  $file2 <: file(body=contains `import { $name } from "./config"`)
}
```

## Limit

Restrict number of matches:

```grit
`console.log($_)` limit 10
```

## Range

Target code by line number:

```grit
range(start_line=5, end_line=10)
```

## Inline Suppression

```javascript
// grit-ignore pattern_name: explanation
console.log("this line won't match");
```

## Common Pitfalls

See [references/pitfalls.md](references/pitfalls.md) for common pitfalls.
