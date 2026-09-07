---
title: Always pass locale to getTranslation
level: error
---

Not passing a locale to `getTranslation` is valid, but causes errors

tags: #correctness

```grit
engine marzano(0.1)
language js

`getTranslation($args)` as $inv where {
  $args <: [$var],
  $inv <: maybe within statement_block(statements=$block) where {
    $block <: contains `const { $p } = $t_func`,
    $t_func <: or { `useTranslation($...)`, `useTranslation()` },
    or {
      and {
        $p <: contains pair_pattern(key=`i18n`, value=$c),
        $c <: contains or {
          pair_pattern(key=`language`, value=$target),
          shorthand_property_identifier_pattern() as $target where {
            $target <: contains `language`
          },
        }
      },
      and {
        $p <: contains `i18n`,
        $target = `i18n.language`
      },
      and {
        $p => `$p, i18n`,
        $target = `i18n.language`
      }
    },

    $args => `$var, $target`
  }
}
```

## Errors

```js
getTranslation(someVar);
```

```js
getTranslation(someVar);
```

## Correct

```js
getTranslation(someVar, locale);
```

## Auto correctable 1

```js
function SomeComponent() {
  const { t } = useTranslation();
  return getTranslation(someVar);
}
```

```js
function SomeComponent() {
  const { t, i18n } = useTranslation();
  return getTranslation(someVar, i18n.language);
}
```

## Auto correctable 2

```js
function SomeComponent() {
  const { t } = useTranslation(['settings']);
  return getTranslation(someVar);
}
```

```js
function SomeComponent() {
  const { t, i18n } = useTranslation(['settings']);
  return getTranslation(someVar, i18n.language);
}
```

## Auto correctable 3

```js
function SomeComponent() {
  const { t, i18n } = useTranslation();
  return getTranslation(someVar);
}
```

```js
function SomeComponent() {
  const { t, i18n } = useTranslation();
  return getTranslation(someVar, i18n.language);
}
```

## Auto correctable 4

```js
function SomeComponent() {
  const {
    i18n: { language },
  } = useTranslation();
  return getTranslation(someVar);
}
```

```js
function SomeComponent() {
  const {
    i18n: { language },
  } = useTranslation();
  return getTranslation(someVar, language);
}
```

## Auto correctable 5

```js
function SomeComponent() {
  const {
    i18n: { language: locale },
  } = useTranslation();
  return getTranslation(someVar);
}
```

```js
function SomeComponent() {
  const {
    i18n: { language: locale },
  } = useTranslation();
  return getTranslation(someVar, locale);
}
```

## Negative Auto Correct

```js
function SomeComponent1() {
  const { t } = useTranslation();
  return t('something');
}
function SomeComponent2() {
  return getTranslation(someVar);
}
```

```js
function SomeComponent1() {
  const { t } = useTranslation();
  return t('something');
}
function SomeComponent2() {
  return getTranslation(someVar);
}
```
