---
title: Unify the load props of the AsyncForm component
---

```grit
engine marzano(0.1)
language js

or {
    `<AsyncForm $p />` as $component where {
        $p <: maybe contains `onError={$handle}` where {
            $handle <: `($e) => $b` where {
                $b <: maybe contains `sendAlert($_)` => .,
                $b <: maybe contains `devLog($dev_string)` => .,
                $dev_string <: contains r"^(['`])Error Loading (.*?)(?: Details| Form)?['`]$"($quote, $id),
                or {
                    and {
                        $dev_string <: contains template_string(),
                        $p => `id={$[quote]$[id]$quote} $p`
                    },
                    $p => `id="$id" $p`
                },
                $e => .,
                $program <: maybe contains `import { sendAlert } from '@example-org/example-app'` where {
                    $program <: not contains `sendAlert($...)` as $s where $s <: not within $b
                } => .,
                $program <: maybe contains `import { devLog } from '~/utils/devLog'` where {
                    $program <: not contains `devLog($...)` as $s where $s <: not within $b
                } => .,
            }
        },
        $p <: contains `loadInitialValues={$values}` where or {
            $values <: `() => Promise.resolve($value_imports)`,
            $values <: `() => $value_imports`,
            and {
                $values <: `$invoke`,
                or {
                    $component <: within statement_block() as $block where {
                        $block <: contains `const $invoke = React.useCallback(() => $replace_i($replace_p), $_)` => .,
                        $value_imports = `$replace_i($replace_p)`
                    },
                    $value_imports = `$invoke()`,
                }
            },
        } => .,
        $p <: contains `loadFormConfig={async ($promise) => {$config}}` where or {
            and {
                $init_default = `initialValues`,
                $config <: contains `const [$p_vars] = await Promise.all([$p_pros])` where or {
                    and {
                        or {
                            $p_vars <: [`$a1`] => `$a1, $init_default`,
                            $p_vars <: [`$a1`, `$init`, $...],
                        },
                        $p_pros <: [`$b1`, `$promise`, $...]
                    },
                    and {
                        or {
                            $p_vars <: [`$a1`, `$a2`] => `$a1, $a2, $init_default`,
                            $p_vars <: [`$a1`, `$a2`, `$init`, $...],
                        },
                        $p_pros <: [`$b1`, `$b2`, `$promise`, $...]
                    },
                    and {
                        or {
                            $p_vars <: [`$a1`, `$a2`, `$a3`] => `$a1, $a2, $a3, $init_default`,
                            $p_vars <: [`$a1`, `$a2`, `$a3`, `$init`, $...],
                        },
                        $p_pros <: [`$b1`, `$b2`, `$b3`, `$promise`, $...]
                    },
                    and {
                        or {
                            $p_vars <: [`$a1`, `$a2`, `$a3`, `$a4`] => `$a1, $a2, $a3, $a4, $init_default`,
                            $p_vars <: [`$a1`, `$a2`, `$a3`, `$a4`, `$init`, $...],
                        },
                        $p_pros <: [`$b1`, `$b2`, `$b3`, `$a4`, `$promise`, $...]
                    },
                    and {
                        or {
                            $p_vars <: [`$a1`, `$a2`, `$a3`, `$a4`, `$a5`] => `$a1, $a2, $a3, $a4, $a5, $init_default`,
                            $p_vars <: [`$a1`, `$a2`, `$a3`, `$a4`, `$a5`, `$init`, $...],
                        },
                        $p_pros <: [`$b1`, `$b2`, `$b3`, `$a4`, `$a5`, `$promise`, $...]
                    },
                },
                if ($init <: ``) {
                    $init = `$init_default`
                },
                if ($init <: not `initialValues`) {
                    $init = `initialValues: $init`
                },
                $config <: contains `$promise` => `$value_imports`,
                $config <: contains `return $form` => `return {
                $init,
                formConfig: $form
                }`
            },
            $config <: contains `return $form` where or {
                $config <: contains `const $v = await $i` => `const [$v, initialValues] = await Promise.all([$i, $value_imports])`,
                $config <: contains `await $promise` => `const initialValues = await $value_imports`
            } => `return {
                initialValues,
                formConfig: $form
            }`,
        } => `load={async () => {$config}}`,
    },
    `export function getOptions($...): $type {$body}` where {
        $type <: contains generic_type(
            name=`Parameters`,
            type_arguments=type_arguments(
                $types
            )
        ) where {
            $types <: contains `typeof`,
            $types <: contains `useAdvancedForm`
        },
        $type <: not contains `NonNullable`,
        $type => `NonNullable<$type>`
    }
}
```
