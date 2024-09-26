---
title: Run refactor
---

```grit
or {
`$type<$t>` => `AbstractField<$t>` where {
    $type <: or {
        `FormContentElement`,
        `TranslatableFormContentElement`
    },
    $source = `type AbstractField`,
    or {
        $program <: contains `import { $i } from $p` where {
            $i <: contains `type FormValues`,
            $source <: ensure_import_from($p)
        },
        $source <: ensure_import_from(`'~/Common/Form/types'`)
    }
},
`import { type AbstractField } from '~/Common/Form/fields/abstract/AbstractField';` => .,
`import { $imports } from $_` where {
    $imports <: contains or {
        `type FormContentElement`,
        `type TranslatableFormContentElement`
    } => .
}
}
```
