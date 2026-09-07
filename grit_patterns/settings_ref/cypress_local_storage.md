---
title: Don't access localStorage directly
level: error
---

Cypress is not async so calls to things like `window.localStorage` or similar must be wrapped in a `cy.then` or use a util.

tags: #cypress

```grit
`window.localStorage.setItem($args)` as $call where {
    $filename <: r"^.*\.cy\.[a-z]+$",
    $call <: not within `$_.then(() => $block)`
} => `cy.setLocalStorage($args)`
```

## Only applies in cypress `.cy` files

```tsx
window.localStorage.setItem('a', 'b');
```

## Replaces localStorage calls with util `.ts`

```ts
// @filename: example.cy.ts
it('test', () => {
  cy.get('...');
  window.localStorage.setItem('a', 'b');
  cy.get('...').should('exist');
});
```

```ts
// @filename: example.cy.ts
it('test', () => {
  cy.get('...');
  cy.setLocalStorage('a', 'b');
  cy.get('...').should('exist');
});
```

## Replaces localStorage calls with util `.tsx`

```ts
// @filename: example.cy.tsx
it('test', () => {
  cy.get('...');
  window.localStorage.setItem('a', 'b');
  cy.get('...').should('exist');
});
```

```ts
// @filename: example.cy.tsx
it('test', () => {
  cy.get('...');
  cy.setLocalStorage('a', 'b');
  cy.get('...').should('exist');
});
```

## Should ignore already wrapped invokes

```ts // @filename: example.cy.ts
it('test', () => {
  cy.get('...');
  cy.then(() => {
    window.localStorage.setItem('a', 'b');
  });
  cy.get('...').should('exist');
});
```
