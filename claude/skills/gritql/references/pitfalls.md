# Common GritQL Pitfalls

1. **Invalid syntax in backticks** — Code inside backticks must parse as valid target-language code. If you need to match a fragment that isn't valid syntax, use AST node patterns instead.
2. **Forgetting bubble** — Always use `bubble` when using `contains` with a rewrite (`=>`). Without it, metavariables from inner and outer scope collide.
3. **Bubble scoping** — Variables inside `bubble` are isolated by default. Use `bubble($var)` to explicitly share variables with the outer scope.
4. **Sequential without contains** — Steps inside `sequential` are not auto-wrapped in `contains`. You must write `contains` explicitly.
5. **Spread in wrong position** — `$...` only works in positions where multiple nodes are valid (argument lists, array elements, object fields, statement lists).
