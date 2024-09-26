---
Title: Upgrade nx project.json to v19 top level
---

```grit
engine marzano(0.1)
language json

`"targets": { $targets }` where {
    $targets <: contains bubble `"$target": { $config }` where {
        $target <: or { `component-test`, `collaboration-test` },
        $config <: contains `"options": { $options }` where {
            $new_pairs = [],
            $options <: contains bubble($new_pairs) pair($key) as $pair where {
                $key <: `"spec"`,
                $new_pairs += $pair
            }
        }
    } => `"$target": { "options": { $new_pairs } }`
}

```
