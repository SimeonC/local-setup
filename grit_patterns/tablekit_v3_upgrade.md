---
title: Removes all tablekit theme references and updates them
---

Switches out Spacing for it's proper usage

tags: #js, #es6, #migration

```grit
engine marzano(0.1)
language js

any {
    `import $_ from '@tablecheck/tablekit-$postfix';` => . where {
        $postfix <: ! r"react|core|react-.*$"
    },
    template_substitution(expressions= `Spacing.$size`) where {
        $size = lowercase($size)
    } => `var(--spacing-$size)`,
    template_substitution(expressions=`({ theme }) => theme.colors.$color`) => `var(--$color)`
}
```
