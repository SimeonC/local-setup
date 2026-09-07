---
title: Consistent string style
level: error
---

Ensures that string style is consistent

tags: #stylistic

```grit
engine marzano(0.1)
language js

template_string($template) where {
    $template <: not contains template_substitution(),
    $template <: not within call_expression() as $call where {
        $call <: r"[a-zA-Z0-9\._]+`[^`]+`"
    },
    $template <: template_content(content=[string_fragment() as $string]),
    $string <: contains r"[^\r\n']*"
} => `'$string'`
```

## Transform strings

```js
const a = 'something';
const b = `something`;
const c = `Record<ModelConfig['root'], string>`;
const d = `something ${a}`;
```

```js
const a = 'something';
const b = 'something';
const c = `Record<ModelConfig['root'], string>`;
const d = `something ${a}`;
```

## Ignore styled components and multiline strings

```js
const a = styled.span`something`;
const b = styled.span`something ${a}`;
const c = styled.span`
  display: block;
`;
const stringBlock = `
              SSL not setup for local development
                                                                      `;
```

## Transform strings in function calls

```jsx
const el = (
  <div
    dangerouslySetInnerHTML={{
      __html: `<span>
      <b>This shouldn't format</b>
    </span>`,
    }}
  />
);
const a = t(`should format`);
const b = css`should not format`;
```

```jsx
const el = (
  <div
    dangerouslySetInnerHTML={{
      __html: `<span>
      <b>This shouldn't format</b>
    </span>`,
    }}
  />
);
const a = t('should format');
const b = css`should not format`;
```
