---
title: Prefer waitForRequest over wait
level: error
---

tags: #cypress

```grit
`cy.wait($args)` as $wait where  {
    $wait <: not within `Cypress.Commands.add('waitForRequest', $_)`,
    $args <: contains r"['`]@legacyApi_([^_]+)_([^'`]+)[`']"($a, $b),
    or {
        $a <: r"\$\{([^}]+)\}"($method),
        $method = `'$a'`
    },
    or {
        $b <: r"\$\{([^}]+)\}"($path),
        and {
            $b <: r".+\$\{.+",
            $path = js"`$b`"
        },
        $path = `'$b'`
    }
} => `cy.waitForRequest({ method: $method, path: $path })`
```

## Transforms wait calls

```ts
cy.wait('@legacyApi_POST_/resources1');
cy.wait('@legacyApi_POST_/resources2');
cy.wait(`@legacyApi_${method}_/resources3`);
cy.wait(`@legacyApi_POST_${path}`);
cy.wait(`@legacyApi_POST_/sub-${path}`);
cy.wait(`@legacyApi_${method}_${path}`);
```

```ts
cy.waitForRequest({ method: 'POST', path: '/resources1' });
cy.waitForRequest({ method: 'POST', path: '/resources2' });
cy.waitForRequest({ method: method, path: '/resources3' });
cy.waitForRequest({ method: 'POST', path: path });
cy.waitForRequest({ method: 'POST', path: `/sub-${path}` });
cy.waitForRequest({ method: method, path: path });
```

## Ignores wait calls in cypress commands

```ts
Cypress.Commands.add('waitForRequest', (options) => {
  cy.log('waitForRequest');
  const { method, path } = parseRequestOptions(options);
  return cy.wait(`@legacyApi_${method}_${path}`).then((i) => handleIntercept(i, path));
});
```
