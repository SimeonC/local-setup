```grit
engine marzano(0.1)
language js

sequential {
    bubble file($body) where $body <: contains bubble or {
      r"([a-zA-Z0-9_-]+)CrudRoute([a-zA-Z0-9_-]+)"($s, $e) => `$[s]ModalFlowType$e`,
      r"([a-zA-Z0-9_-]+)CrudRoute"($s) => `$[s]ModalFlowType`,
      `getAllEnumValues(CrudRoute)` where {
          $import = `modalFlows`,
          $import <: ensure_import_from(`"~/Router/types"`)
      } => `modalFlows`,
      `CrudRoute.$enum` as $s where {
          $r = lowercase($enum),
          or {
              $enum <: within template_substitution() => `$r`,
              $s => `'$r'`,
          }
      },
      `\`${CrudRoute}\` | (CrudRoute & {})` => `ModalFlowType`,
      `CrudRoute` => `ModalFlowType`,
      `export enum CrudRoute {$...}` => `export const modalFlows = ['edit', 'create', 'clone', 'restore'] as const;
  export type ModalFlowType = (typeof modalFlows)[number];`
  },
  bubble file($body) where $body <: maybe contains remove_unused_imports(`"~/Router/types"`)
}
```

## Replaces Enum Type usage

```tsx
import { type CrudRoute } from '~/Router/types';

function getTypeFromCrudRoute(type: `${CrudRoute}` | Mutation): Mutation {}
```

```tsx
import { type ModalFlowType } from '~/Router/types';

function getTypeFromModalFlowType(type: `${ModalFlowType}` | Mutation): Mutation {}
```

## Replaces iteration type usages

```tsx
import { type CrudRoute } from '~/Router/types';

getAllEnumValues(CrudRoute).includes(part as CrudRoute);
```

```tsx
import { type ModalFlowType, modalFlows } from '~/Router/types';

modalFlows.includes(part as ModalFlowType);
```

## Replaces Enum type usages in switch

```ts
function FlowTitle({ modelTranslation, flow }: { modelTranslation: string; flow: CrudRoute }) {
  const { t } = useTranslation(['legacy']);

  switch (flow) {
    case CrudRoute.Create:
    case CrudRoute.Clone:
      return t('legacy:actions.new_model', { model: modelTranslation });
    case CrudRoute.Restore:
      return t('legacy:actions.restore_model', { model: modelTranslation });
    case CrudRoute.Edit:
      return t('legacy:actions.edit_model', { model: modelTranslation });
  }
}
```

```ts
function FlowTitle({ modelTranslation, flow }: { modelTranslation: string; flow: ModalFlowType }) {
  const { t } = useTranslation(['legacy']);

  switch (flow) {
    case 'create':
    case 'clone':
      return t('legacy:actions.new_model', { model: modelTranslation });
    case 'restore':
      return t('legacy:actions.restore_model', { model: modelTranslation });
    case 'edit':
      return t('legacy:actions.edit_model', { model: modelTranslation });
  }
}
```

## Simplifies expansive types

```ts
function someFunc(opts: { flow?: `${CrudRoute}` | (CrudRoute & {}) }) {}
```

```ts
function someFunc(opts: { flow?: ModalFlowType }) {}
```

## Removes string interpolation

```ts
import { CrudRoute } from '~/Router/types';
void navigate(buildPath(`/items/${CrudRoute.Edit}/${record.id}`));
```

```ts
void navigate(buildPath(`/items/edit/${record.id}`));
```

## Removes original enum

```ts
export enum CrudRoute {
  Edit = 'edit',
  Create = 'create',
  Clone = 'clone',
  Restore = 'restore',
}
```

```ts
export const modalFlows = ['edit', 'create', 'clone', 'restore'] as const;
export type ModalFlowType = (typeof modalFlows)[number];
```
