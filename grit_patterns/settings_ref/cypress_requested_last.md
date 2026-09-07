---
title: Prefer shouldHaveRequestedLast over chaining waitForRequest
level: error
---

tags: #cypress

```grit
`cy.waitForRequest($arg).its('$req').should('$t', $param)` where {
      $t <: contains or { "deep.equal", "deep.match", "deep.nested.include", "include" },
      or {
          and {
              $req <: contains "request",
              $param <: `{ body: $b }` => $b
          },
          and {
              $req <: contains "request.body"
          }
      }
  } => `cy.shouldHaveRequestedLast($arg, $param)`
```

## Transform request include

```ts
cy.waitForRequest({ method: 'POST', path: '/messages' })
  .its('request.body')
  .should('deep.nested.include', {
    message: {
      name_translations: {
        en: 'New Name',
      },
      sender_type: 'from',
      email_type: 'custom',
      email: 'test@test.com',
    },
  });
cy.waitForRequest({ method: 'PUT', path: '/user' }).its('request.body').should('include', {
  first_name: 'John',
});
cy.waitForRequest({ method: 'PUT', path: '/user' })
  .its('request.body')
  .should('not.include.any.keys', 'current_password', 'password_confirmation', 'password');
```

```ts
cy.shouldHaveRequestedLast(
  { method: 'POST', path: '/messages' },
  {
    message: {
      name_translations: {
        en: 'New Name',
      },
      sender_type: 'from',
      email_type: 'custom',
      email: 'test@test.com',
    },
  },
);
cy.shouldHaveRequestedLast(
  { method: 'PUT', path: '/user' },
  {
    first_name: 'John',
  },
);
cy.waitForRequest({ method: 'PUT', path: '/user' })
  .its('request.body')
  .should('not.include.any.keys', 'current_password', 'password_confirmation', 'password');
```

## Transform request deep equals

```ts
cy.waitForRequest({ method: 'DELETE', path: '/items/bulk' })
  .its('request.body')
  .should('deep.equal', { ids: ['12', '14', '123'], tenant_id: 'tenant-1' });
```

```ts
cy.shouldHaveRequestedLast(
  { method: 'DELETE', path: '/items/bulk' },
  { ids: ['12', '14', '123'], tenant_id: 'tenant-1' },
);
```
