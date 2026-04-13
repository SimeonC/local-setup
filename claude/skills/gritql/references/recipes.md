# GritQL Pattern Recipes

Recipes below show the *pattern*. Apply via:

```bash
grit apply '<pattern>' --dry-run
```

## Find function/method calls

- All calls to a specific function: `` `fetchData($...)` ``
- Method calls on a specific object: `` `logger.$method($...)` ``
- Chained calls: `` `$_.then($...).catch($...)` ``

## Find imports

- Imports from a specific package: `` `import $_ from "lodash"` ``
- Named imports: `` `import { $_ } from "react"` ``
- Require calls: `` `require("express")` ``

## Find definitions

- Function definitions: `` `function $name($...) { $_ }` ``
- Arrow functions assigned to const: `` `const $name = ($...) => $_` ``
- Class definitions: `` `class $name { $_ }` ``
- Type/interface definitions: `` `interface $name { $_ }` ``

## Find usages in context

- Find usage inside async functions: `` `await $fn($...)` ``
- Find usage inside try/catch: `` `try { $body } catch($_) { $_ }` where { $body <: contains `$target($...)` } ``
- Find usage inside specific function: `` `function handleSubmit($...) { $body }` where { $body <: contains `validate($...)` } ``

## Find patterns with conditions

- Find variables matching a regex: `` `const $name = $_` where { $name <: r"^use[A-Z]" } ``
- Find calls with specific argument count: `` `$fn($a, $b, $c, $...rest)` where { $fn <: `createServer` } ``

## Find by file

- Search only test files: `` `describe($_, $...)` `` with path filter `'**/*.test.*'`
- Search only in src/: `` `console.log($...)` `` with path filter `src/`
