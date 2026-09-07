---
title: Use the getByTestId/findByTestId/childrenByTestId helpers
level: error
---

For cross compatibility with other libraries, familiarity and ease of use, use the `xxxByTestId` helpers

tags: #cypress

```grit
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
        and {
            or {
                $method <: `find` => `findByTestId`,
                $method <: `get` => `getByTestId`,
                $method <: `closest` => `closestByTestId`,
                $method <: `parents` => `parentsByTestId`,
                $method <: `children` => `childrenByTestId`,
                $method <: `next` => `nextByTestId`,
                and {
                  $pre <: `cy`,
                  $method <: `contains` => `testIdContains`
                }
            },
            or {
                $target <: r`'(?:div|span|button)?\\[data-test[iI]d="([^"\\]]+)"?\\]?'`($id) => `'$id'`,
                $target <: r`"(?:div|span|button)?\\[data-test[iI]d='([^'\\]]+)'?\\]?"`($id) => `'$id'`,
                $target <: template_string(
                    template=template_content(
                        content=[
                            r`\\[data-test[iI]d="`,
                                template_substitution($expression),
                            r`"?\\]?`
                        ]
                    )
                ) => $expression,
                $target <: template_string(
                    template=template_content(
                        content=[
                            or {
                                r`\\[data-test[iI]d="([^"\\]]+)`($pre_content) => $pre_content,
                                r`\\[data-test[iI]d="` => .,
                            },
                            template_substitution($expression),
                            or {
                                r`([^"\\]]+)"?\\]?`($post_content) => $post_content,
                                r`"?\\]?` => .,
                            }
                        ]
                    )
                ),
            }
        },
    }
}
```

## Basic Tests

```ts
cy.get('[data-testid="Some Id"]');
cy.get("[data-testid='Copy Tables']").click();
cy.get('[data-testid="Some Id"]').click();
cy.get('[data-testid="Form Header"]').find('[data-testid="Send Test Email"]').click();
cy.get(`[data-testid="${var}"]`);
cy.get(`[data-testid="${fieldName}-delete"]`).click();
cy.get(`[data-testid="add-${fieldName}"]`).click();
cy.get(`[data-testid="add-${fieldName}-delete"]`).click();
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
cy.getByTestId('Copy Tables').click();
cy.getByTestId('Some Id').click();
cy.getByTestId('Form Header').findByTestId('Send Test Email').click();
cy.getByTestId(var);
cy.getByTestId(`${fieldName}-delete`).click();
cy.getByTestId(`add-${fieldName}`).click();
cy.getByTestId(`add-${fieldName}-delete`).click();
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

## Negative Chains Children

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

## Negative Chains Siblings

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

## Chains Other

```ts
cy.get('[data-testid="App Notice Audience Locales Filter"]').selectComponentOption({ value: 'en' });
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
cy.getByTestId('App Notice Audience Locales Filter').selectComponentOption({ value: 'en' });
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
cy.get('[data-testid="one"] .some-selector .other .selector [data-testid="two"]');
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
cy.get('[data-testid="one"]', { timeout: 100 });
```

```ts
cy.getByTestId('one', { timeout: 100 });
```

## Correcting common errors

```ts
cy.get('[data-testid="Some Id"');
cy.get('[data-testid="Some Id');
cy.get('[data-testid="Some Id]');
```

```ts
cy.getByTestId('Some Id');
cy.getByTestId('Some Id');
cy.getByTestId('Some Id');
```
