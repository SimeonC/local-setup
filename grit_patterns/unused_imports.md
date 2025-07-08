---
title: Run remove unused imports
---

```grit
pattern internal_remove_unused_imports($src) {
or {
    `import * as $import_clause from $src`,
    `import $import_clause, { $named_imports } from $src` where {
        $named_imports <: maybe some bubble($keep_named_import_list) or {`type $_ as $import`, `type $import`, `$_ as $import`, `$import`} as $full where {
            if($program <: contains `$import` until `import $_`) {
                $keep_named_import_list = true
             } else {
                $full => .
            }
        }
    },
    `import $import_clause from $src` where { $import_clause <: not contains `{$_}`},
} as $import_line where {
    $import_clause <: or {`type $module_name`, `$module_name`},
    $program <: not contains $module_name until `import $_`,
    if($keep_named_import_list <: undefined) {
        $import_line => .
    } else {
        $import_clause => .
    }
  }
}

internal_remove_unused_imports()
```
