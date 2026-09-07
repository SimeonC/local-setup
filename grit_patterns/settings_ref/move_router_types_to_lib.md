---
title: Moving some of the generated types from apps/sample-app to libs/router
---

```grit
engine marzano(0.1)
language js

or {
    `import { $types } from '~/Router/types.gen'` where {
        $types <: contains bubble or { `type AllRoutePaths`, `type FormFlowPaths` } as $i where {
            $i <: ensure_import_from(`'@local/router'`)
        } => .
    },
    `import { $types } from '~/Router/types'` where {
        $types <: contains bubble or { `modalFlows`, `type ModalFlowType`, `assertModalFlow` } as $i where {
            $i <: ensure_import_from(`'@local/router'`)
        } => .
    }
}
```

## Change import when AllRoutePaths is the only import

```ts
import { type AllRoutePaths } from '~/Router/types.gen';
```

```ts
import { type AllRoutePaths } from '@local/router';
```

## Change import when FormFlowPaths is the only import

```ts
import { type FormFlowPaths } from '~/Router/types.gen';
```

```ts
import { type FormFlowPaths } from '@local/router';
```

## Move the specified imports to the new location

```ts
import { type AllRoutePaths, type RouteFoldersTree, type FormFlowPaths } from '~/Router/types.gen';
```

```ts
import { type RouteFoldersTree } from '~/Router/types.gen';
import { type AllRoutePaths, type FormFlowPaths } from '@local/router';
```

## Doesn't change imports without desired exports

```ts
import { type RouteFoldersTree } from '~/Router/types.gen';
```

## Moves ModalFlow values

```ts
import { modalFlows, type ModalFlowType, assertModalFlow } from '~/Router/types';
```

```ts
import { modalFlows, type ModalFlowType, assertModalFlow } from '@local/router';
```

## Correctly splits out other imports

```ts
import { modalFlows, type NavConfigType, assertModalFlow } from '~/Router/types';
```

```ts
import { type NavConfigType } from '~/Router/types';
import { modalFlows, assertModalFlow } from '@local/router';
```
