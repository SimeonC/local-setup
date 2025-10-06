---
title: Run console.log debugging and test debugging
---

Check for my local debugging removals

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
    $args <: contains or { string_fragment(), string() } as $s where {
        $s <: contains r".*\[debug\].*"
    }
  },
  or { `only` } as $modifier where {
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
console.log('[debug] remove me');
console.log('[debug]', 'remove me');
console.dir('remove me [debug]');
console.info('remove [debug] me');
console.log('keep me 1');
console.dir('keep me 2');
console.info('keep me 3');
console.error('keep me 4');
console.warn('keep me 5');
```

```ts
console.log('keep me 1');
console.dir('keep me 2');
console.info('keep me 3');
console.error('keep me 4');
console.warn('keep me 5');
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
const actorContext = createActorContext(
  priorityMachine,
  { devTools: true },
  (state) => {}
);
const actorContext = createActorContext(
  priorityMachine,
  { devTools: true },
  (state) => {
    console.log('some debugging', state);
  }
);
const actorContext = createActorContext(
  priorityMachine,
  undefined,
  (state) => {}
);
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  console.log('some debugging', state);
});
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  someOtherActor.send({});
});
const actorContext = createActorContext(
  priorityMachine,
  { devTools: true },
  (state) => {
    someOtherActor.send({});
  }
);
```

```ts
const actorContext = createActorContext(priorityMachine, { devTools: true });
const actorContext = createActorContext(priorityMachine, { devTools: true });
const actorContext = createActorContext(priorityMachine);
const actorContext = createActorContext(priorityMachine);
const actorContext = createActorContext(priorityMachine, undefined, (state) => {
  someOtherActor.send({});
});
const actorContext = createActorContext(
  priorityMachine,
  { devTools: true },
  (state) => {
    someOtherActor.send({});
  }
);
```
