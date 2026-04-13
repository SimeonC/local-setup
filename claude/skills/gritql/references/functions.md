# GritQL Built-in Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `capitalize($str)` | Uppercase first char | `capitalize("foo")` → `"Foo"` |
| `uppercase($str)` | All uppercase | `uppercase("foo")` → `"FOO"` |
| `lowercase($str)` | All lowercase | `lowercase("FOO")` → `"foo"` |
| `trim($str)` | Strip whitespace | `trim("  foo  ")` → `"foo"` |
| `join(list, separator)` | Join list to string | `join(list=$items, separator=", ")` |
| `split($str, separator)` | Split string to list | `split($str, separator=",")` |
| `length($list)` | Count elements | `length($items)` |
| `distinct($list)` | Remove duplicates | `distinct($items)` |
| `text($node)` | Get node text as string | `text($expr)` |
| `log($msg)` | Debug logging | `log($var)` |
| `resolve($path)` | Resolve relative path | `resolve("./foo")` |
