---
title: Keep react-i18next usage consistent
level: error
---

tags: #stylistic

```grit
`$var = useTranslation($_)` where or {
    $var <: array_pattern(elements=[$t]) where or {
        $t <: `t`,
        and {
            $var <: r"\[,.*",
            or {
                $t <: `i18n`,
                $t => `i18n: $t`,
            }
        },
        $t => `t: $t`,
    } => `{ $t }`,
    $var <: array_pattern(elements=[$t, $i]) where {
        or {
            $t <: `t` => `$t,`,
            $t => `t: $t,`,
        },
        or {
            $i <: `i18n`,
            $i => `i18n: $i`,
        }
    } => `{ $t $i }`,
}
```

## Converts inconsistent `useTranslation` hooks

```ts
const [t] = useTranslation();
const [t2] = useTranslation();
const [t] = useTranslation('settings');
const [t, i18n] = useTranslation();
const [t2, i18n2] = useTranslation();
const [, { language }] = useTranslation();
const [t, i18n] = useTranslation(['settings']);
```

```ts
const { t } = useTranslation();
const { t: t2 } = useTranslation();
const { t } = useTranslation('settings');
const { t, i18n } = useTranslation();
const { t: t2, i18n: i18n2 } = useTranslation();
const {
  i18n: { language },
} = useTranslation();
const { t, i18n } = useTranslation(['settings']);
```

## Ignores correct `useTranslation` hooks

```ts
const { t } = useTranslation();
const { t } = useTranslation(['settings']);
const { t, i18n } = useTranslation();
const { t, i18n: i18n2 } = useTranslation();
const { t, i18n } = useTranslation(['settings']);
```
