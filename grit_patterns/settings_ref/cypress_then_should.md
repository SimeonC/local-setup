---
title: Use should callback instead of should in then
level: error
---

Calls inside a .then are not retried, using .should will be retried and is prefered for better test robustness.

tags: #cypress

```grit
predicate handle_args($filtered_args, $check, $args) {
  $check_string = $args[0],
  $check_string <: `'$check_inner'`,
  $check = $check_inner,
  $args <: some bubble($check_string, $filtered_args) `$arg` where or {
    $arg <: $check_string,
    $filtered_args += $arg
  },
  $filtered_args = join(list=$filtered_args, separator=",")
}

`$pre_chain.$method(($...) => { $body })` where or {
  and {
    $method <: `then` => `should`,
    $body <: not contains `cy.get($...)`,
    $body <: not contains `cy.getByTestId($...)`,
    $body <: some bubble expression_statement() as $expr where {
      $check = ``,
      $filtered_args = [],
      or {
        $expr <: `cy.wrap($node).should($args);` where {
          handle_args($filtered_args, $check, $args)
        } => `expect($node).to.$check($filtered_args);`,
        $expr <: `cy.wrap($node).should($args).$rest;` where {
          handle_args($filtered_args, $check, $args)
        } => `expect($node).to.$check($filtered_args).$rest;`,
      },
    },
    $import = `expect`,
    $import <: ensure_import_from(`"local-cypress"`),
  },
  and {
    $method <: `then`,
    $body <: not contains `cy.get($...)`,
    $body <: not contains `cy.getByTestId($...)`,
    $body <: contains `$_.should($...)`,
    $pre_chain <: contains `cy.get($_)`
  },
}
```

## Test 1

```tsx
cy.get('[data-sortableid]').then((els) => {
  const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
  cy.wrap(actualIds).should('deep.equal', expectedIds);
});
cy.get('something').then(() => {
  cy.get('[data-sortableid]').then((els) => {
    const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
    cy.wrap(actualIds).should('deep.equal', expectedIds);
  });
});
```

```tsx
import { expect } from 'local-cypress';

cy.get('[data-sortableid]').should((els) => {
  const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
  expect(actualIds).to.deep.equal(expectedIds);
});
cy.get('something').then(() => {
  cy.get('[data-sortableid]').should((els) => {
    const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
    expect(actualIds).to.deep.equal(expectedIds);
  });
});
```

## Test 2

```tsx
cy.get('[data-testid="Quick Link"]')
  .should('have.length', 6)
  .then((links) => {
    cy.wrap(links.eq(0)).should('contain', 'dashboard.content.edit_menu');
    cy.wrap(links.eq(1)).should('contain', 'dashboard.content.change_business_hours');
    cy.wrap(links.eq(2)).should('contain', 'dashboard.content.tables');
    cy.wrap(links.eq(3)).should('contain', 'dashboard.content.configure_venues');
    cy.wrap(links.eq(4)).should('contain', 'dashboard.content.review_users');
    cy.wrap(links.eq(5)).should('contain', 'dashboard.content.survey');
  });
```

```tsx
import { expect } from 'local-cypress';

cy.get('[data-testid="Quick Link"]')
  .should('have.length', 6)
  .should((links) => {
    expect(links.eq(0)).to.contain('dashboard.content.edit_menu');
    expect(links.eq(1)).to.contain('dashboard.content.change_business_hours');
    expect(links.eq(2)).to.contain('dashboard.content.tables');
    expect(links.eq(3)).to.contain('dashboard.content.configure_venues');
    expect(links.eq(4)).to.contain('dashboard.content.review_users');
    expect(links.eq(5)).to.contain('dashboard.content.survey');
  });
```

## Multi Arg Should

```tsx
cy.get('[data-testid="Accordion"]')
  .click()
  .then(($el) => {
    cy.wrap($el.siblings('div').eq(0)).should('have.attr', 'data-state', bool ? 'closed' : 'open');
  });
```

```tsx
import { expect } from 'local-cypress';

cy.get('[data-testid="Accordion"]')
  .click()
  .should(($el) => {
    expect($el.siblings('div').eq(0)).to.have.attr('data-state', bool ? 'closed' : 'open');
  });
```

## No Change Test

```tsx
cy.get('[data-sortableid]').then((els) => {
  const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
  const el = cy.wrap(actualIds);
  el.should('deep.equal', expectedIds);
});
```

```tsx
cy.get('[data-sortableid]').then((els) => {
  const actualIds = [...els].map((el) => el.getAttribute('data-sortableid'));
  const el = cy.wrap(actualIds);
  el.should('deep.equal', expectedIds);
});
```

## Negative test

```tsx
cy.get('#output').then(($output) => {
  const output = $output.html();
  cy.get('input + button').click();
  cy.get(`[data-date="${targetDate}"]`).click();
  cy.get('input').invoke('val').should('equal', output);
  cy.get('button[type=submit]').click();
  cy.wrap(submit).should('have.been.calledOnceWith', {
    date: new Date(`${targetDate}T00:00`),
  });
});

cy.get('#output').then(($output) => {
  const output = $output.html();
  cy.getByTestId('some-id').click();
  cy.wrap(submit).should('have.been.calledOnceWith', {
    date: new Date(`${targetDate}T00:00`),
  });
});

cy.currentUserResponse().then(({ accessible_tenants_by_id: shops, current_user: user }) => {
  cy.url().should('equal', `${Cypress.env('baseUrl')}/${tenants[user.primary_tenant_id!].slug}`);
});
```
