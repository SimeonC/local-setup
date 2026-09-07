---
title: Playwright Migration - change all the getByTestId/findByTestId/childrenByTestId helpers
---

This

tags: #cypress

```grit
function split_selectors($method, $selectors, $opts) js {
  const selector = $selectors.text;
  const method = $method.text;

  const result = [];
  let current = '';
  let inBrackets = 0;
  let inParens = 0;
  let inQuotes = false;
  let quoteChar = '';

  for (let i = 0; i < selector.length; i++) {
    const char = selector[i];

    // Handle quotes
    if ((char === '"' || char === "'") && !inQuotes) {
      inQuotes = true;
      quoteChar = char;
    } else if (char === quoteChar && inQuotes) {
      inQuotes = false;
      quoteChar = '';
    }

    // Skip processing if we're inside quotes
    if (inQuotes) {
      current += char;
      continue;
    }

    // Track brackets and parentheses
    if (char === '[') inBrackets++;
    else if (char === ']') inBrackets--;
    else if (char === '(') inParens++;
    else if (char === ')') inParens--;

    // Only split on combinators when not inside brackets/parens
    if (inBrackets === 0 && inParens === 0) {
      // Check for explicit combinators: >, +, ~
      if (char === '>' || char === '+' || char === '~') {
        if (current.trim()) result.push(current.trim());
        result.push(char);
        current = '';
        continue;
      }

      // Handle spaces (potential descendant combinators)
      if (char === ' ') {
        // Look ahead to see if this space is followed by more spaces
        let j = i + 1;
        while (j < selector.length && selector[j] === ' ') {
          j++;
        }

        // If we have content and the space is followed by non-combinator content
        if (current.trim() && j < selector.length &&
            selector[j] !== '>' && selector[j] !== '+' && selector[j] !== '~') {
          result.push(current.trim());
          result.push(' '); // descendant combinator
          current = '';
          // Skip all the spaces we found
          i = j - 1;
          continue;
        }
      }
    }

    current += char;
  }

  // Add final part
  if (current.trim()) {
    result.push(current.trim());
  }

  // Clean up any empty strings or duplicate spaces
  const parts = result.map(p=>p.trim()).filter(part => part !== '');

  function extractTestId(selector) {
    // Match [data-testid="value"] or [data-testid='value'] or [data-testid=value]
    const match = selector.trim().match(/^(?:div|span|button)?\[data-testid=["']?([^"'\]]+)["']?\]$/i);
    return match ? match[1] : null;
  }

  function handleAccumulated() {
    if (!accumulatedNonIds.length) return;
    const p = accumulatedNonIds.join(' ');
    const opById = currentOperatorById || 'findByTestId';
    const op = currentOperator || 'find';
    accumulatedNonIds = [];
    currentOperatorById = '';
    currentOperator = '';
    return argsChain.push(`).${op}(${p === '*' ? '' : `'${p}'`}`);
  }

  const argsChain = [];
  let currentOperatorById;
  let currentOperator;
  switch (method) {
    case 'get': {
      currentOperatorById = 'getByTestId';
      currentOperator = 'get';
      break;
    }
    case 'find': {
      currentOperatorById = 'findByTestId';
      currentOperator = 'find';
      break;
    }
    case 'children': {
      currentOperatorById = 'childrenByTestId';
      currentOperator = 'children';
      break;
    }
    case 'parents': {
      currentOperatorById = 'parentsByTestId';
      currentOperator = 'parents';
      break;
    }
    case 'closest': {
      currentOperatorById = 'closestByTestId';
      currentOperator = 'closest';
      break;
    }
  }
  let accumulatedNonIds = [];
  parts.forEach((p,index) => {
    const testId = extractTestId(p);
    if (accumulatedNonIds.length && testId) {
      handleAccumulated();
    }
    if (p === '>') {
        handleAccumulated();
        currentOperatorById = 'childrenByTestId';
        currentOperator = 'children';
        return;
    }
    if (p === '+') {
        handleAccumulated();
        currentOperatorById = 'nextByTestId';
        currentOperator = 'next';
        return;
    }
    if (!testId) {
      accumulatedNonIds.push(p);
      return;
    }
    const opById = currentOperatorById || 'findByTestId';
    const op = currentOperator || 'find';
    currentOperatorById = '';
    currentOperator = '';
    argsChain.push(`).${opById}('${testId}'`);
  });
  handleAccumulated();
  const optsArg = $opts && $opts.text ? `,${$opts.text}` : '';
  return `${argsChain.join('').substring(2)}${optsArg})`
}

`$pre.$method($target_args)` as $statement where {
    $statement <: contains `cy.$chain`,
    $statement <: not contains `cy.$$($_)`,
    $statement <: not within `Cypress.Commands.add($name, $...)` where {
        $name <: r`.*[tT]estId.*`
    },
    or {
        $target_args <: [$target, $opts],
        $target_args <: [$target],
    },
    or {
        $target <: r`'((?:.* +)?(?:div|span|button)?\\[data-test[iI]d="[^"]+"\\](?:[ >+~].+)?)'`($selectors) where {
            $method <: not `contains`,
            or {
                $target_args <: [$target, $opts] where {
                    $new = split_selectors($method, $selectors, $opts),
                },
                $new = split_selectors($method, $selectors, opts = ``),
            },
            $statement => raw`$pre.$new`
        },
        and {
            or {
                $method <: `find` => `findByTestId`,
                $method <: `get` => `getByTestId`,
                $method <: `closest` => `closestByTestId`,
                and {
                  $pre <: `cy`,
                  $method <: `contains` => `testIdContains`
                }
            },
            or {
                $target <: r`'(?:div|span|button)?\\[data-test[iI]d="([^"]+)"\\]?'`($id) => `'$id'`,
                $target <: template_string(
                    template=template_content(
                        content=[
                            r`\\[data-test[iI]d="([^"]*)`($r1) => $r1,
                            $var,
                            r`([^"\\[]_)"\\] (.*)`($r2, $rest) => $r2,
                            $rest2
                        ]
                    )
                ) where {
                    $chain = template_string(template=template_content(content=[$rest, $rest2]))
                },
                $target <: template_string(
                    template=template_content(
                        content=[
                            r`\\[data-test[iI]d="`,
                                template_substitution($expression),
                            r`"\\] (.+)`($rest),
                            $rest2
                        ]
                    )
                ) where {
                    $chain = template_string(template=template_content(content=[$rest, $rest2]))
                } => $expression,
                $target <: template_string(
                    template=template_content(
                        content=[
                            r`\\[data-test[iI]d="`,
                                template_substitution($expression),
                            r`"\\]?`,
                        ]
                    )
                ) => $expression,
            }
        },
        $target <: r`'(.+)[>] ?\\[data-test[iI]d="([^"]+)"\\]?'`($find, $id) where {
            $statement => `$statement.nextByTestId('$id')`
        } => `'$find'`,
        $target <: r`'(.+)[+] ?\\[data-test[iI]d="([^"]+)"\\]?'`($find, $id) where {
            $statement => `$statement.nextByTestId('$id')`
        } => `'$find'`,
        $target <: r`'(.+) \\[data-test[iI]d="([^"]+)"\\]?'`($find, $id) where {
            $statement => `$statement.findByTestId('$id')`
        } => `'$find'`,
    }
}
```

## Basic Tests

```ts
cy.get('[data-testid="Some Id"]');
cy.get('[data-testid="Some Id"]').click();
cy.get(
      '[data-testid="Form Header"] [data-testid="Send Test Email"]',
    ).click();
cy.get(`[data-testid="${var}"]`);
cy.get('div [data-testid="Some Id"]');
cy.get('div').find('[data-testid="Some Id"]');
cy.get('div').find(`[data-testid="${var}"]`);
cy.get('div[data-testid="tenant_ids"]').selectComponentOption({
  value: 'tenant-1',
});
cy.get('button[data-testid="Some Id"]').click();
cy.get('span[data-testid="Some Id"]').click();
cy.contains('[data-testid="Combos Grid"]', 'Something').should('exist');
```

```ts
cy.getByTestId('Some Id');
cy.getByTestId('Some Id').click();
cy.getByTestId('Form Header').findByTestId('Send Test Email').click();
cy.getByTestId(var);
cy.get('div').findByTestId('Some Id');
cy.get('div').findByTestId('Some Id');
cy.get('div').findByTestId(var);
cy.getByTestId('tenant_ids').selectComponentOption({
  value: 'tenant-1',
});
cy.getByTestId('Some Id').click();
cy.getByTestId('Some Id').click();
cy.testIdContains('Combos Grid', 'Something').should('exist');
```

## Chains Basic

```ts
cy.get('[data-testid="one"] div');
cy.get('[data-testid="one"] [data-testid="two"]');
cy.get('[data-testid="one"] [data-testid="two"] [data-testid="three"]');
```

```ts
cy.getByTestId('one').find('div');
cy.getByTestId('one').findByTestId('two');
cy.getByTestId('one').findByTestId('two').findByTestId('three');
```

## Chains Children

```ts
cy.get('[data-testid="one"] > div');
cy.get('[data-testid="one"] > *');
cy.get('[data-testid="one"]>[data-testid="two"]');
cy.get('[data-testid="one"]> [data-testid="two"]');
cy.get('[data-testid="one"] > [data-testid="two"]');
cy.get('[data-testid="one"] >[data-testid="two"]');
cy.get('[data-testid="one"] > div [data-testid="two"]');
cy.get('[data-testid="one"] > * [data-testid="two"]');
cy.get('[data-testid="Text Editor Input"] > [contenteditable="true"]').focus();
cy.get('[data-testid="Text Editor Input"] > div > *').should('have.length', 1);
```

```ts
cy.getByTestId('one').children('div');
cy.getByTestId('one').children();
cy.getByTestId('one').childrenByTestId('two');
cy.getByTestId('one').childrenByTestId('two');
cy.getByTestId('one').childrenByTestId('two');
cy.getByTestId('one').childrenByTestId('two');
cy.getByTestId('one').children('div').findByTestId('two');
cy.getByTestId('one').children().findByTestId('two');
cy.getByTestId('Text Editor Input').children('[contenteditable="true"]').focus();
cy.getByTestId('Text Editor Input').children('div').children().should('have.length', 1);
```

## Chains Siblings

```ts
cy.get('[data-testid="one"] + div');
cy.get('[data-testid="one"] + *');
cy.get('[data-testid="one"]+[data-testid="two"]');
cy.get('[data-testid="one"]+ [data-testid="two"]');
cy.get('[data-testid="one"] + [data-testid="two"]');
cy.get('[data-testid="one"] +[data-testid="two"]');
cy.get('[data-testid="one"] + div [data-testid="two"]');
cy.get('[data-testid="one"] div + [data-testid="two"]');
cy.get('[data-testid="one"] + * [data-testid="two"]');
cy.get(
  '[data-testid="Color Picker"] + [data-testid="Variables"] + [data-testid="Element Align"]',
).should('exist');
```

```ts
cy.getByTestId('one').next('div');
cy.getByTestId('one').next();
cy.getByTestId('one').nextByTestId('two');
cy.getByTestId('one').nextByTestId('two');
cy.getByTestId('one').nextByTestId('two');
cy.getByTestId('one').nextByTestId('two');
cy.getByTestId('one').next('div').findByTestId('two');
cy.getByTestId('one').find('div').nextByTestId('two');
cy.getByTestId('one').next().findByTestId('two');
cy.getByTestId('Color Picker')
  .nextByTestId('Variables')
  .nextByTestId('Element Align')
  .should('exist');
```

## Chains Other

```ts
cy.get('[data-testid="one"] .some-selector .other .selector [data-testid="two"]');
cy.get('[data-testid="App Notice Audience Locales Filter"]').selectComponentOption({ value: 'en' });
cy.get('[data-testid="Menu Item Row"][data-id="menu-item-2"] [data-testid="Name"]').should(
  'have.text',
  'Shop 2 Item',
);
cy.get(`[data-testid="Global Alert"] [data-context="${context}"]`)
  .closest('[data-testid="Closest"]')
  .find('[data-testid="Find"]')
  .children('[data-testid="Children"]')
  .click();
cy.get('[data-testid="question_1_ui_type"]')
  .parents('[data-testid="Form Section"]')
  .get('label button[data-variant="ghost"]')
  .click();
```

```ts
cy.getByTestId('one').find('.some-selector .other .selector').findByTestId('two');
cy.getByTestId('App Notice Audience Locales Filter').selectComponentOption({ value: 'en' });
cy.get('[data-testid="Menu Item Row"][data-id="menu-item-2"]')
  .findByTestId('Name')
  .should('have.text', 'Shop 2 Item');
cy.get(`[data-testid="Global Alert"] [data-context="${context}"]`)
  .closestByTestId('Closest')
  .findByTestId('Find')
  .childrenByTestId('Children')
  .click();
cy.getByTestId('question_1_ui_type')
  .parentsByTestId('Form Section')
  .get('label button[data-variant="ghost"]')
  .click();
```

## Negative Tests - basic

```ts
[].find('[data-testid="bob"]');
cy.get('other').contains('new-test').click();
cy.contains('not test id', 'other').should('exist');
```

## Negative Tests - complex chain

```ts
cy.get('[data-testid="Menu Item Row"][data-id="menu-item-2"] .name').should(
  'have.text',
  'Shop 2 Item',
);
```

## Negative Tests - Commands add

```ts
Cypress.Commands.add(
  'getByTestId',
  (selector, options) => cy.get(`[data-testid="${selector}"]`, options) as never,
);

Cypress.Commands.add(
  'findByTestId',
  {
    prevSubject: true,
  },
  (subject, selector) => cy.wrap(subject).find(`[data-testid="${selector}"]`),
);

Cypress.Commands.add(
  'childrenByTestId',
  {
    prevSubject: true,
  },
  (subject, selector) => cy.wrap(subject).children(`[data-testid="${selector}"]`),
);
```

## Negative Tests - contains $$

```ts
cy.wait(100).then(() => {
  const dialogConfirm = cy.$$('body [data-testid="Prompt Dialog"] [data-testid="Confirm"]');
  if (dialogConfirm.length === 0) {
    return;
  }
  cy.wrap(dialogConfirm).click();
});
```

## Preserves options

```ts
cy.get('[data-testid="one"] div', { timeout: 100 });
cy.get('[data-testid="one"] [data-testid="two"]', { timeout: 100 });
cy.get('[data-testid="one"] [data-testid="two"] [data-testid="three"]', { timeout: 100 });
```

```ts
cy.getByTestId('one').find('div', { timeout: 100 });
cy.getByTestId('one').findByTestId('two', { timeout: 100 });
cy.getByTestId('one').findByTestId('two').findByTestId('three', { timeout: 100 });
```

## Correcting common errors

```ts
cy.get('[data-testid="Some Id"');
cy.get('div [data-testid="Some Id"');
```

```ts
cy.getByTestId('Some Id');
cy.get('div').findByTestId('Some Id');
```
