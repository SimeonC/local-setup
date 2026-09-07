---
title: check for and remove debugging
level: error
---

Check for common debugging removals

tags: #cleanup

```grit
private pattern match_any_test_function() {
    or {
        `test`, `it`, `describe`, `context`
    }
}

or {
  `cy.pause()` => .,
  `console.$method($args);` as $log => . where {
    $filename <: not r".*\/(?:vite-plugins|scripts?)\/.*",
    $method <: not or {
      `error`, `warn`
    },
    ! $log <: after r"// oxlint-disable-next-line .*?no-console.*"
  },
  or { `only`, `skip` } as $modifier where {
    $modifier <: within member_expression($object, property=`$modifier`) where {
        $object <: match_any_test_function()
    } => $object,
    $modifier <: within call_expression(arguments=$args) where {
        ! $args <: contains r"// TODO .*",
        ! $args <: contains statement_block(statements=[]),
    }
  },
  `createActorContext($_, $opts, $subscription)` where {
      $opts <: maybe `undefined` => .,
      $subscription <: or {
        `($...) => {}`,
        `($...) => {
          console.log($...)
        }`
      } => .
  }
}
```

## Removes `cy.pause()` calls

```ts
cy.pause();
```

```ts

```

## Remove `console.log` debugging

```ts
console.log('remove me');
console.dir('remove me');
console.info('remove me');
// oxlint-disable-next-line no-console
console.log('keep me');
// oxlint-disable-next-line something-else,no-console
console.dir('keep me');
// oxlint-disable-next-line no-console,other
console.info('keep me');
console.error('keep me');
console.warn('keep me');
```

```ts
// oxlint-disable-next-line no-console
console.log('keep me');
// oxlint-disable-next-line something-else,no-console
console.dir('keep me');
// oxlint-disable-next-line no-console,other
console.info('keep me');
console.error('keep me');
console.warn('keep me');
```

## remove `.only` and `.skip`

The exceptions are if we have a todo comment or an empty test body

```ts
it.only('only', () => {
  cy.get('...');
});
it.skip('skip', () => {
  cy.get('...');
});
it.only('keep only', () => {
  // TODO something something
  cy.get('...');
});
it.skip('keep skip', () => {
  // TODO something something
  cy.get('...');
});
it.only('keep', () => {});
it.skip('keep', () => {});
it('normal', () => {
  cy.get('...');
});
```

```ts
it('only', () => {
  cy.get('...');
});
it('skip', () => {
  cy.get('...');
});
it.only('keep only', () => {
  // TODO something something
  cy.get('...');
});
it.skip('keep skip', () => {
  // TODO something something
  cy.get('...');
});
it.only('keep', () => {});
it.skip('keep', () => {});
it('normal', () => {
  cy.get('...');
});
```

## remove empty createActor state subscription

```ts
const actorContext = createActorContext(priorityMachine, { devTools: true }, (state) => {});
const actorContext = createActorContext(priorityMachine, { devTools: true }, (state) => {
  console.log('some debugging', state);
});
const actorContext = createActorContext(priorityMachine, undefined, (state) => {});
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  console.log('some debugging', state);
});
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  someOtherActor.send({});
});
const actorContext = createActorContext(priorityMachine, { devTools: true }, (state) => {
  someOtherActor.send({});
});
```

```ts
const actorContext = createActorContext(priorityMachine, { devTools: true });
const actorContext = createActorContext(priorityMachine, { devTools: true });
const actorContext = createActorContext(priorityMachine);
const actorContext = createActorContext(priorityMachine);
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  someOtherActor.send({});
});
const actorContext = createActorContext(priorityMachine, { devTools: true }, (state) => {
  someOtherActor.send({});
});
```
