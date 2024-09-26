---
title: Cleanup development debugging
level: error
---

tags: #js, #es6, #cleanup

```grit

engine marzano(0.1)
language js

private pattern match_any_test_functionlocal() {
    or {
        `test`, `it`, `describe`, `context`, `Cypress.dualTest`
    }
}

pattern remove_debug() {
    or {
        `cy.pause()` => .,
        `console.log($args);` as $log => . where {
            and {
                $args <: contains r"'\[debug\][^']*'",
                ! $log <: after r"// eslint-disable-next-line .*?no-console.*"
            }
        },
        `$domain.$modifier($args)` where {
            and {
                $domain <: match_any_test_functionlocal(),
                $modifier <: r"^(?:only|skip).*$",
                ! $args <: contains r"// TODO .*",
                ! $args <: contains statement_block(statements=[]),
                ! $domain <: within `$alias.$parentModifier = ($...) => { $_ }`,
                ! $domain <: within `function runWhen($...) { $_ }`
            }
        } => `$domain($args)`
    }
}

pattern fix_verbose_axios() {
    or {
        and { `axios<$type>({ $props })`, $type_final = raw`<$type>` },
        and { `axios({ $props })`, $type_final = raw`` }
    } where {
        $args = [],
        $props <: contains `method: '$method'` where { or {
            $method <: contains "GET",
            and {
                or {
                    $method <: contains "PUT",
                    $method <: contains "POST"
                },
                $props <: contains `data: $data` => .,
                $args += $data
            }
        } } => .,
        $method = lowercase($method),
        $props <: contains `url: $url` => .,
        $args += `{ $props }`,
        $args = join($args, ", ")
    } => `axios.$method$type_final($url, $args)`
}

pattern fix_misquoted_tests() {
    `$func($args)` where {
        $args <: [string() as $string, or { arrow_function(), function() }],
        $func <: r"context|describe|it",
        $string <: r`^(['\`])([^"]+)"([^"]+)(['\`])$`($q1, $s1, $s2, $q2) => `$q1"$s1"$s2$q2`
    }
}

any {
    remove_debug(),
    fix_verbose_axios(),
    fix_misquoted_tests()
}
```
