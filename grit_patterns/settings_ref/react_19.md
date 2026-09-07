---
title: Upgrade to react 19
---

tags: #upgrade, #refactor

```grit
private pattern jsx_types() {
    `JSX.Element` as $e where {
        if ($program <: contains `import * as $i from 'react'`) {
            $e => `$i.JSX.Element`
        } else {
            $import = `JSX`,
            $import <: ensure_import_from(`'react'`)
        }
    }
}

private pattern use_ref_initial_value() {
    call_expression($arguments, $function, $type_arguments) as $call where {
        $function <: contains `useRef`,
        $arguments <: [],
        or {
            and {
                $type_arguments <: contains `null`,
                $type_arguments <: not contains union_type(),
                $call => `$function(null)`
            },
            and {
                $type_arguments <: type_arguments(types=[union_type() as $union]) where {
                    $union <: maybe contains or {
                        r`^((?:.|\n)+)\\| ?null$`($rest) => `$rest`,
                        r`^(.*)null ?\\| ?(.*)$`($start, $rest) => `$start$rest`
                    },
                },
                $call => `$function$type_arguments(null)`
            },
            $call => `$function$type_arguments(null)`
        },
    }
}

private pattern replace_mutable_ref_object() {
    or {
        `MutableRefObject<$type>` => `RefObject<$type>`,
        `React.MutableRefObject<$type>` => `React.RefObject<$type>`
    } where {
        $type <: not contains `null`,
        $type <: contains `undefined` => `null`,
    }
}

or {
    jsx_types(),
    use_ref_initial_value(),
    replace_mutable_ref_object(),
    `import { mount } from 'cypress/react18';` => `import { mount } from 'cypress/react';`
}

```

## Adds react import for JSX

This import will be fixed with the eslint plugin rule autofixer

```tsx
function Component(): JSX.Element {
  return <div />;
}
const Component2 = (): JSX.Element => {
  return <div />;
};
```

```tsx
import { JSX } from 'react';

function Component(): JSX.Element {
  return <div />;
}
const Component2 = (): JSX.Element => {
  return <div />;
};
```

## Uses existing import if existing

```tsx
import * as React from 'react';
function Component(): JSX.Element {
  return <div />;
}
const Component2 = (): JSX.Element => {
  return <div />;
};
```

```tsx
import * as React from 'react';
function Component(): React.JSX.Element {
  return <div />;
}
const Component2 = (): React.JSX.Element => {
  return <div />;
};
```

## Fixes useRef initial value

```tsx
const r = React.useRef();
const r = React.useRef<Type | null>();
const r = React.useRef<null | Type>();
const r = React.useRef<Type | null | Type2>();
const r = React.useRef<null>();
const r = useRef();
const r = useRef<Type>();
const r = React.useRef(true);
const r = React.useRef<Type>(true);
const r = useRef(true);
const r = useRef<Type>(true);
```

```tsx
const r = React.useRef(null);
const r = React.useRef<Type>(null);
const r = React.useRef<Type>(null);
const r = React.useRef<Type | Type2>(null);
const r = React.useRef(null);
const r = useRef(null);
const r = useRef<Type>(null);
const r = React.useRef(true);
const r = React.useRef<Type>(true);
const r = useRef(true);
const r = useRef<Type>(true);
```

## Fixes useRef types and initialValue

```tsx
export function useDateMask(
  dateFormat: string,
  onChange: (newDate: Date | undefined) => void,
): {
  ref: React.MutableRefObject<HTMLInputElement | undefined>;
  maskRef: React.MutableRefObject<IMask.InputMask<IMask.AnyMaskedOptions> | undefined>;
  format: (date: Date | undefined) => string;
} {
  const ref = React.useRef<HTMLInputElement>();
  const maskRef = React.useRef<IMask.InputMask<IMask.AnyMaskedOptions>>();
  const ref2 = React.useRef<HTMLInputElement>(other);
  const maskRef2 = React.useRef<IMask.InputMask<IMask.AnyMaskedOptions>>(undefined);
}
```

```tsx
export function useDateMask(
  dateFormat: string,
  onChange: (newDate: Date | undefined) => void,
): {
  ref: React.RefObject<HTMLInputElement | null>;
  maskRef: React.RefObject<IMask.InputMask<IMask.AnyMaskedOptions> | null>;
  format: (date: Date | undefined) => string;
} {
  const ref = React.useRef<HTMLInputElement>(null);
  const maskRef = React.useRef<IMask.InputMask<IMask.AnyMaskedOptions>>(null);
  const ref2 = React.useRef<HTMLInputElement>(other);
  const maskRef2 = React.useRef<IMask.InputMask<IMask.AnyMaskedOptions>>(undefined);
}
```
