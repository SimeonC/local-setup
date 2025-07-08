---
title: Run refactor
---

```grit
engine marzano(0.1)
language js

function strip_last($pre) js {
    return $pre.text.replace(/[a-z-]+: $/ig, '');
}

function extract_style($pre) js {
    const match = /.*?([a-z-]+): $/ig.exec($pre.text);
    if (!match) return $pre.text;
    return match[1].split('-').map((s,i) => i === 0 ? s.toLowerCase() : s.slice(0, 1).toUpperCase() + s.slice(1).toLowerCase()).join('');
}

function strip_leading($post) js {
    return $post.text.replace(/^;?/ig, '');
}

or { `const $var = styled($_)($string)`, `const $var = styled.$_($string)` } where {
    $string <: contains bubble($var, $string) `({ $prop }) => $prop && $value` as $int where {
        $int <: within template_substitution() as $sub,
        $string <: contains template_content($content) where {
            $content <: [$..., string_fragment() as $pre, $sub => ., $post, $...],
            $style = extract_style($pre),
            $pre => strip_last($pre),
            $post => strip_leading($post),
        },
        $program <: contains bubble($var, $prop, $style, $value) or { `<$var $props />`, `<$var $props>$_</$var>` } where {
            $props <: contains `$prop={$pass_prop}` as $pair,
            $value <: contains `$prop` => `$pass_prop`,
            or {
                $props <: contains `style={{ $styles }}` where {
                    $styles => `$styles, $style: $value`,
                    $pair => .
                },
                $pair => `style={{ $style: $value }}`
            }
        }
    }
}
```

## (test)

```tsx
const CategoryName = styled('span')`
  cursor: pointer;
  ${({ hasSubcategories }) =>
    hasSubcategories &&
    css`
      &:before {
        margin-right: 0.5rem;
        font-weight: 400;
      }
    `};
`;

const CategoryName = styled.span`
  cursor: pointer;
  ${({ hasSubcategories }) =>
    hasSubcategories &&
    css`
      &:before {
        margin-right: 0.5rem;
        font-weight: 400;
      }
    `};
`;

const BackgroundImage = styled.div<{ image: string | null }>`
  background-image: ${({ image }) => image && `url(${image})`};
  background-repeat: no-repeat;
  background-size: cover;
  background-position: center;
  background-attachment: fixed;
`;

const a = <BackgroundImage image={background} />;
const b = <BackgroundImage image={background} style={{ color: 'blue' }} />;

const a = (
  <BackgroundImage image={background}>
    <div />
  </BackgroundImage>
);
const b = (
  <BackgroundImage image={background} style={{ color: 'blue' }}>
    <div />
  </BackgroundImage>
);
```

```tsx
const CategoryName = styled('span')`
  cursor: pointer;
  ${({ hasSubcategories }) =>
    hasSubcategories &&
    css`
      &:before {
        margin-right: 0.5rem;
        font-weight: 400;
      }
    `};
`;

const CategoryName = styled.span`
  cursor: pointer;
  ${({ hasSubcategories }) =>
    hasSubcategories &&
    css`
      &:before {
        margin-right: 0.5rem;
        font-weight: 400;
      }
    `};
`;

const BackgroundImage = styled.div<{ image: string | null }>`
  background-repeat: no-repeat;
  background-size: cover;
  background-position: center;
  background-attachment: fixed;
`;

const a = <BackgroundImage style={{ backgroundImage: `url(${background})` }} />;
const b = (
  <BackgroundImage
    style={{ color: 'blue', backgroundImage: `url(${background})` }}
  />
);

const a = (
  <BackgroundImage style={{ backgroundImage: `url(${background})` }}>
    <div />
  </BackgroundImage>
);
const b = (
  <BackgroundImage
    style={{ color: 'blue', backgroundImage: `url(${background})` }}
  >
    <div />
  </BackgroundImage>
);
```
