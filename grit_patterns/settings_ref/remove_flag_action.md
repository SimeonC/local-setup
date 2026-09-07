---
title: Remove flag
---

Usage: `grit apply 'remove_flag(flag="users-import")'`

```grit
engine marzano(0.1)
language js

private pattern remove_element_import($flag) {
    `import { $imports } from '$_'` where {
        not $program <: contains `<FeatureFlagSwitch $props />` as $el where {
            $props <: contains jsx_attribute(name=`flag`) as $attr,
            $attr <: not contains $flag,
        },
        $imports <: contains `FeatureFlagSwitch` => .,
    }
}

private pattern remove_use_flag_toggle_hook_import($flag) {
    `import { $imports } from '$_'` where {
        not $program <: contains `useFeatureFlag($arg)` where {
            $arg <: not contains $flag,
        },
        $imports <: contains `useFeatureFlag` => .,
    }
}

private pattern remove_element($flag) {
    `<FeatureFlagSwitch $props />` as $el where {
        $props <: contains jsx_attribute(name=`flag`, value = contains string_fragment() as $value) where or {
            and {
                $value <: r`!$flag`,
                or {
                    and {
                        $props <: contains `renderInactive={() => {$block return $replace }}`,
                        $el => `$replace`,
                        $el <: within or { return_statement(), lexical_declaration() } as $state => `$block $state`
                    },
                    and {
                        $props <: contains or { `renderInactive={() => ($replace)}`, `renderInactive={() => $replace}` },
                        $el => `$replace`
                    },
                    and {
                        $props <: contains `renderInactive={$component}`,
                        $el => `<$component />`
                    },
                    and {
                        $el <: within jsx_element(),
                        $el => .,
                    },
                    $el => `null`
                }
            },
            and {
                $value <: `$flag`,
                or {
                    and {
                        $props <: contains `renderActive={() => {$block return $replace }}`,
                        $el => `$replace`,
                        $el <: within or { return_statement(), lexical_declaration() } as $state => `$block $state`
                    },
                    and {
                        $props <: contains or { `renderActive={() => ($replace)}`, `renderActive={() => $replace}` },
                        $el => `$replace`
                    },
                    and {
                        $props <: contains `renderActive={$component}`,
                        $el => `<$component />`
                    },
                    and {
                        $el <: within jsx_element(),
                        $el => .,
                    },
                    $el => `null`
                }
            },
        }
    }
}

private pattern remove_use_flag_toggle_hook($flag) {
    `const $v = useFeatureFlag('$flag')` where {
        or {
            and {
                $v <: `{ isActive, $... }`,
                $var = `isActive`
            },
            $v <: `{ isActive: $var, $... }`,
            and {
                $v <: `{ flagValue, $... }`,
                $var = `flagValue`
            },
            $v <: `{ flagValue: $var, $... }`,
        },
        $v <: within statement_block() as $block where {
            $block <: contains bubble($var) or {
                if_statement(condition=parenthesized_expression(expression=`!$var`),alternative = else_clause(else = or { `{ $r }`, `$r` })) => `$r`,
                if_statement(condition=parenthesized_expression(expression=or {
                    binary_expression(left=`$var`, operator=`||`),
                    binary_expression(operator=`||`, right=`$var`),
                    `$var`
                }),consequence = or { `{ $r }`, `$r` }) => `$r`,
                binary_expression(left=`$var`, operator=`&&`, $right) => $right,
                binary_expression($left, operator=`&&`, right=`$var`) => $left,
                or {
                    binary_expression(left=`$var`, operator=`||`),
                    binary_expression(operator=`||`, right=`$var`)
                } => `true`,
                shorthand_property_identifier() => `$var: true`,
                $var => `true`
            }
        }
    } => .
}

private pattern remove_flag_value($flag) {
  or {
    `flag: '!$flag'` as $p where {
      $p <: within object() as $o,
      $o => .
    },
    `flag: '$flag'` => .,
  }
}

private pattern remove_tests($flag) {
    `checkAllFeatureFlagsIncluded([$flags])` where {
        $flags <: contains `'$flag'` => .
    }
}

pattern remove_flag($flag) {
    or {
        remove_element($flag),
        remove_use_flag_toggle_hook($flag),
        remove_element_import($flag),
        remove_use_flag_toggle_hook_import($flag),
        remove_flag_value($flag),
        remove_tests($flag),
    }
}

remove_flag(flag="example-flag")
```

## Cleans up Flag values

```ts
export const paymentsLinks: SidenavLink[] = [
  {
    type: 'link',
    entity: 'test',
    action: 'update',
    to: '/test',
    labelKey: 'models:settings',
    labelOptions: { count: 2 },
    flag: 'example-flag',
  },
  {
    type: 'link',
    entity: 'test',
    action: 'update',
    to: '/test',
    labelKey: 'models:settings',
    labelOptions: { count: 2 },
    flag: '!example-flag',
  },
];
```

```ts
export const paymentsLinks: SidenavLink[] = [
  {
    type: 'link',
    entity: 'test',
    action: 'update',
    to: '/test',
    labelKey: 'models:settings',
    labelOptions: { count: 2 },
  },
];
```

## Cleans up Test setup

```ts
Cypress.Commands.add('login', (value, optionalPermissions, optionalAbility) => {
  cy.then(() => {
    cy.session(userId, () => {
      checkAllFeatureFlagsIncluded([
        'example-flag',
        'flag-other-1',
        'flag-other-2',
      ]).forEach((flag) => {
        window.localStorage.setItem(`settings_flag_${flag}`, 'on');
      });
      window.localStorage.setItem('settings_viewed_walkthrough', 'all');
    });
  });
});
```

```ts
Cypress.Commands.add('login', (value, optionalPermissions, optionalAbility) => {
  cy.then(() => {
    cy.session(userId, () => {
      checkAllFeatureFlagsIncluded([
        'flag-other-1',
        'flag-other-2',
      ]).forEach((flag) => {
        window.localStorage.setItem(`settings_flag_${flag}`, 'on');
      });
      window.localStorage.setItem('settings_viewed_walkthrough', 'all');
    });
  });
});
```

## Removes matching `FlagToggle` elements and cleans import

```tsx
import { FeatureFlagSwitch } from '...';
const a = <FeatureFlagSwitch flag="example-flag" />;
```

```tsx
const a = null;
```

## Removes matching `FlagToggle` elements and does not clean import if still used

```tsx
import { FeatureFlagSwitch } from '...';
const a = <FeatureFlagSwitch flag="example-flag" />;
const b = <FeatureFlagSwitch flag="another-flag" />;
```

```tsx
import { FeatureFlagSwitch } from '...';
const a = null;
const b = <FeatureFlagSwitch flag="another-flag" />;
```

## Ignores not-matching `FlagToggle` elements

```tsx
const a = <FeatureFlagSwitch flag="another-flag" />;
const b = <FeatureFlagSwitch flag="another-flag" renderActive={() => null} />;
const c = <FeatureFlagSwitch flag="another-flag" renderInactive={() => null} />;
const d = (
  <FeatureFlagSwitch flag="another-flag" renderActive={() => null} renderInactive={() => null} />
);
```

## Replace matching `FlagToggle` elements with active content

```tsx
const a = <FeatureFlagSwitch flag="example-flag" renderInactive={() => <div>Content</div>} />;
const b = <FeatureFlagSwitch flag="example-flag" renderActive={() => <div>Content</div>} />;
const c = <FeatureFlagSwitch flag="!example-flag" renderInactive={() => <div>Content</div>} />;
const d = <FeatureFlagSwitch flag="!example-flag" renderActive={() => <div>Content</div>} />;
function Component() {
  return (
    <FeatureFlagSwitch
      flag="example-flag"
      renderActive={() => {
        const vara = 'a';
        return <div>Content</div>;
      }}
    />
  );
}
```

```tsx
const a = null;
const b = <div>Content</div>;
const c = <div>Content</div>;
const d = null;
function Component() {
  const vara = 'a';
  return <div>Content</div>;
}
```

## Replace matching `FlagToggle` elements with active component

```tsx
const a = <FeatureFlagSwitch flag="example-flag" renderActive={ActiveComponent} />;
const b = <FeatureFlagSwitch flag="!example-flag" renderActive={ActiveComponent} />;
```

```tsx
const a = <ActiveComponent />;
const b = null;
```

## Correctly handle matching `FlagToggle` elements with only inactive content

```tsx
const a = <FeatureFlagSwitch flag="example-flag" renderInactive={() => <div>Content</div>} />;
const b = <FeatureFlagSwitch flag="!example-flag" renderInactive={() => <div>Content</div>} />;
function Component1() {
  return <FeatureFlagSwitch flag="example-flag" renderInactive={() => <div>Content</div>} />;
}
function Component2() {
  return (
    <div>
      <FeatureFlagSwitch flag="example-flag" renderInactive={() => <div>Content</div>} />
    </div>
  );
}
```

```tsx
const a = null;
const b = <div>Content</div>;
function Component1() {
  return null;
}
function Component2() {
  return <div></div>;
}
```

## removes and cleans up hook usages of `useFeatureFlag`

```tsx
import { useFeatureFlag } from '~/Common/Flags';

function useSimple() {
  const { isActive } = useFeatureFlag('example-flag');
  return isActive;
}

function useSimple2() {
  const { flagValue } = useFeatureFlag('example-flag');
  return flagValue;
}

function useObject() {
  const { isActive } = useFeatureFlag('example-flag');
  return { isActive };
}

function useObject2() {
  const { flagValue } = useFeatureFlag('example-flag');
  return { flagValue };
}

function useArray() {
  const { isActive: isMe } = useFeatureFlag('example-flag');
  return [isMe];
}

function useArray2() {
  const { flagValue: value } = useFeatureFlag('example-flag');
  return [value];
}
```

```tsx
function useSimple() {
  return true;
}

function useSimple2() {
  return true;
}

function useObject() {
  return { isActive: true };
}

function useObject2() {
  return { flagValue: true };
}

function useArray() {
  return [true];
}

function useArray2() {
  return [true];
}
```

## ignores other hook usages of `useFeatureFlag`

```tsx
import { useFeatureFlag } from '~/Common/Flags';

function useSimple() {
  const { isActive: isA } = useFeatureFlag('example-flag');
  const { isActive: isB } = useFeatureFlag('another-flag');
  return isA && isB;
}

function useSimple2() {
  const { flagValue: valueA } = useFeatureFlag('example-flag');
  const { flagValue: valueB } = useFeatureFlag('another-flag');
  return valueA && valueB;
}
```

```tsx
import { useFeatureFlag } from '~/Common/Flags';

function useSimple() {
  const { isActive: isB } = useFeatureFlag('another-flag');
  return isB;
}

function useSimple2() {
  const { flagValue: valueB } = useFeatureFlag('another-flag');
  return valueB;
}
```

## handles branching for `useFeatureFlag`

```tsx
function MyComponent() {
  const { isActive: isA } = useFeatureFlag('example-flag');
  if (isA) {
    return 'a';
  }
  if (isA) return 'inline';
  if (isA || isOther) return 'b';
  if (isA && isOther) return 'c';
  if (!isA) return 'remove';
  else return 'negative else';
  if (isOther) return 'other';
  else if (isA) return 'else-if';
  else return 'remove';
  if (isA) return 'else';
  else return 'remove';
  return null;
}

function MyComponent2() {
  const { flagValue: value } = useFeatureFlag('example-flag');
  if (value) {
    return 'a';
  }
  if (value) return 'inline';
  if (value || isOther) return 'b';
  if (value && isOther) return 'c';
  if (!value) return 'remove';
  else return 'negative else';
  if (isOther) return 'other';
  else if (value) return 'else-if';
  else return 'remove';
  if (value) return 'else';
  else return 'remove';
  return null;
}
```

```tsx
function MyComponent() {
  return 'a';
  return 'inline';
  return 'b';
  if (isOther) return 'c';
  return 'negative else';
  if (isOther) return 'other';
  else return 'else-if';
  return 'else';
  return null;
}

function MyComponent2() {
  return 'a';
  return 'inline';
  return 'b';
  if (isOther) return 'c';
  return 'negative else';
  if (isOther) return 'other';
  else return 'else-if';
  return 'else';
  return null;
}
```
