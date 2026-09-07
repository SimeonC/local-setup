---
title: Use helper functions for legacy requests
---

tags: #cypress

```grit
predicate replace_spy($method, $path, $should, $call) {
    or {
        and {
            $should <: [`'have.been.calledWithMatch'`, `$match`] where {
                $match <: `{ body: $body }` => `$body`
            } => $match,
            $call => `cy.shouldHaveRequestedWith({ method: $method, path: $path }, $should)`,
        },
        and {
            or {
                $should <: `'not.have.been.called'` => `0`,
                $should <: `'have.been.calledOnce'` => `1`,
                $should <: `'be.calledOnce'` => `1`,
                $should <: `'have.been.calledTwice'` => `2`,
                $should <: `'be.calledTwice'` => `2`,
                $should <: [`'have.callCount'`, `$times`] => $times
            },
            $call => `cy.shouldHaveRequestedTimes({ method: $method, path: $path }, $should)`,
        },
        and {
            $should <: `'be.called'`,
            $call => `cy.shouldHaveRequested({ method: $method, path: $path })`
        },
    },
}

or {
    `cy.$name($arg).should($should)` as $call where {
        or {
            and {
                $name <: `get`,
                $arg <: contains r"@legacyApi_([^_]+)_(.*):spy"($method, $path),
                replace_spy(`'$method'`, `'$path'`, $should, $call)
            },
            and {
                $name <: `getLegacyApiSpy`,
                $arg <: [`$method`, `$path`],
                replace_spy($method, $path, $should, $call)
            }
        },
    },
    `cy.waitForLegacyApi($a, $b).its($r).should($s, $t)` where {
        $s <: contains or { "deep.match", "deep.equal", "deep.nested.include", "includes", "include" },
        or {
            and {
                $r <: contains "request",
                $t <: `{ body: $b }` => $b
            },
            and {
                $r <: contains "request.body"
            }
        },
    } => `cy.shouldHaveRequestedWith({ method: $a, path: $b }, $t)`,
    `cy.waitForLegacyApi($a, $b)` => `cy.waitForRequest({ method: $a, path: $b })`,
    `cy.waitForLegacyApi($a)` => `cy.waitForRequest($a)`,
    `cy.legacyApi($args)` where or {
        $args <: [`$m`, `$p`, `$r`, `$o`] => `{ method: $m, path: $p, response: $r, options: $o }`,
        $args <: [`$m`, `$p`, `$r`] => `{ method: $m, path: $p, response: $r }`
    } => `cy.mockRequest($args)`,
    `cy.legacyApi($args)` => `cy.mockRequest($args)`
}
```

## Transforms waitFor

```ts
cy.waitForLegacyApi('POST', '/items');
cy.waitForLegacyApi('POST', '/items')
  .its('request.body')
  .should('deep.nested.include', { prop: 'a' });
```

```ts
cy.waitForRequest({ method: 'POST', path: '/items' });
cy.shouldHaveRequestedWith({ method: 'POST', path: '/items' }, { prop: 'a' });
```

## Transforms waitForLegacyApi/Api

```ts
cy.waitForLegacyApi('POST', '/resources')
  .its('request.body')
  .then((exampleResource: ExampleResourceAPI) => {
    expectStringMatch(exampleResource, 'color_primary_fill', chroma(primary).hex());
  });
cy.waitForLegacyApi({ api: someApi, method: 'create' })
  .its('request.body')
  .then((exampleResource: ExampleResourceAPI) => {
    expectStringMatch(exampleResource, 'color_primary_fill', chroma(primary).hex());
  });
cy.waitForLegacyApi('PUT', `/accounts/${defaultUsers[1].id}`)
  .its('request.body')
  .should('deep.nested.include', { a: 1 });
```

```ts
cy.waitForRequest({ method: 'POST', path: '/resources' })
  .its('request.body')
  .then((exampleResource: ExampleResourceAPI) => {
    expectStringMatch(exampleResource, 'color_primary_fill', chroma(primary).hex());
  });
cy.waitForRequest({ api: someApi, method: 'create' })
  .its('request.body')
  .then((exampleResource: ExampleResourceAPI) => {
    expectStringMatch(exampleResource, 'color_primary_fill', chroma(primary).hex());
  });
cy.shouldHaveRequestedWith(
  { method: 'PUT', path: `/accounts/${defaultUsers[1].id}` },
  { a: 1 },
);
```

## Transforms spys

```ts
cy.getLegacyApiSpy('POST', '/audience_count').should('have.been.calledWithMatch', {
  body: {
    audience: {
      name: '',
      currency: 'local',
      customer_tags: ['vip1'],
    },
  },
});
cy.getLegacyApiSpy('GET', '/user_permissions/*').should('be.calledOnce');
cy.get('@legacyApi_GET_/resources:spy').should('have.been.calledOnce');
cy.getLegacyApiSpy('GET', '/resources').should('have.been.calledOnce');
cy.get('@legacyApi_GET_/resources:spy').should('have.been.calledTwice');
cy.getLegacyApiSpy('GET', '/resources').should('have.been.calledTwice');
cy.get('@legacyApi_POST_/items/bulk:spy').should('not.have.been.called');
cy.getLegacyApiSpy('POST', '/items/bulk').should('not.have.been.called');
cy.get('@legacyApi_POST_/files:spy').should('be.called');
cy.getLegacyApiSpy('POST', '/files').should('be.called');
cy.get('@legacyApi_PUT_/groups/:id:spy').should('have.callCount', 5);
cy.getLegacyApiSpy('PUT', '/groups/:id').should('have.callCount', 5);
```

```ts
cy.shouldHaveRequestedWith(
  { method: 'POST', path: '/audience_count' },
  {
    audience: {
      name: '',
      currency: 'local',
      customer_tags: ['vip1'],
    },
  },
);
cy.shouldHaveRequestedTimes({ method: 'GET', path: '/user_permissions/*' }, 1);
cy.shouldHaveRequestedTimes({ method: 'GET', path: '/resources' }, 1);
cy.shouldHaveRequestedTimes({ method: 'GET', path: '/resources' }, 1);
cy.shouldHaveRequestedTimes({ method: 'GET', path: '/resources' }, 2);
cy.shouldHaveRequestedTimes({ method: 'GET', path: '/resources' }, 2);
cy.shouldHaveRequestedTimes({ method: 'POST', path: '/items/bulk' }, 0);
cy.shouldHaveRequestedTimes({ method: 'POST', path: '/items/bulk' }, 0);
cy.shouldHaveRequested({ method: 'POST', path: '/files' });
cy.shouldHaveRequested({ method: 'POST', path: '/files' });
cy.shouldHaveRequestedTimes({ method: 'PUT', path: '/groups/:id' }, 5);
cy.shouldHaveRequestedTimes({ method: 'PUT', path: '/groups/:id' }, 5);
```

## Transform request include

```ts
cy.waitForLegacyApi('POST', '/messages')
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
cy.waitForLegacyApi('PUT', '/user').its('request.body').should('include', {
  first_name: 'John',
});
cy.waitForLegacyApi('PUT', '/user')
  .its('request.body')
  .should('not.include.any.keys', 'current_password', 'password_confirmation', 'password');
```

```ts
cy.shouldHaveRequestedWith(
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
cy.shouldHaveRequestedWith(
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
cy.waitForLegacyApi('POST', '/items/bulk')
  .its('request.body')
  .should('deep.equal', {
    table_ids: ['1', '2', '3', '4'],
  });
cy.waitForLegacyApi('DELETE', '/items/bulk')
  .its('request.body')
  .should('deep.equal', { ids: ['12', '14', '123'], tenant_id: 'tenant-1' });
```

```ts
cy.shouldHaveRequestedWith(
  { method: 'POST', path: '/items/bulk' },
  {
    table_ids: ['1', '2', '3', '4'],
  },
);
cy.shouldHaveRequestedWith(
  { method: 'DELETE', path: '/items/bulk' },
  { ids: ['12', '14', '123'], tenant_id: 'tenant-1' },
);
```

## Transforms cy.legacyApi and cy.legacyApi

```ts
cy.legacyApi('GET', `/items/${records[0].id}`, {
  records: [records[0]],
});
cy.legacyApi(
  'GET',
  '/delivery_statistics',
  {
    delivery_statistics: deliveryStatistics,
  },
  {
    times: 1,
  },
);
cy.legacyApi({
  api: menuItemsApi,
  method: 'list',
  response: [
    {
      id: '1',
      menu_category_id: '1',
      slug: 'slug-1',
    },
  ],
});
```

```ts
cy.mockRequest({
  method: 'GET',
  path: `/items/${records[0].id}`,
  response: {
    records: [records[0]],
  },
});
cy.mockRequest({
  method: 'GET',
  path: '/delivery_statistics',
  response: {
    delivery_statistics: deliveryStatistics,
  },
  options: {
    times: 1,
  },
});
cy.mockRequest({
  api: menuItemsApi,
  method: 'list',
  response: [
    {
      id: '1',
      menu_category_id: '1',
      slug: 'slug-1',
    },
  ],
});
```
