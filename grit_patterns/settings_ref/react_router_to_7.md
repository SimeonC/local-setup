```grit
engine marzano(0.1)
language js

or {
  `<Route $props />` where {
    $props <: contains jsx_attribute(name=`path`, $value) where {
      $value <: string(),
      $value <: contains string_fragment() as $path where {
        $path <: r"(.*)\/\*"($parent)
      }
    } => .
  } => `<Route path="$parent"><Route path="*" $props /></Route>`,
  `import $old from 'react-router-dom'` as $dom_import where or {
    and {
      $new_imports = [],
      $program <: contains `import { $i } from 'react-router'` where {
        $i <: contains bubble($new_imports) import_specifier() as $c where {
          $new_imports += $c
        }
      },
      $old <: contains bubble($new_imports) import_specifier() as $c where {
        $new_imports += $c
      },
      $new_imports = join(list=$new_imports, separator=`, `),
      $i => `$new_imports`,
      $dom_import => .
    },
    $dom_import => `import $old from 'react-router'`
  },
  within_same_block(target = `const $var = useRoutePathBuilder()`, predicate = contains bubble ($var) `$var($string)` where {
    $string <: contains r"^([`'])/(.*)$"($q, $r) => `$q$r`
  }),
}
```

## convert import

```tsx
import * as React from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';

import { CrudRoute } from '~/Router/types';

import { ExampleForm } from './ExampleForm';
import { ExamplesHome } from './ExamplesHome';

export function ExamplePages(): React.JSX.Element | null {
  return (
    <>
      <ExamplesHome />
      <Routes>
        <Route
          path={`${CrudRoute.Edit}/:surveyId`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route
          path={`${CrudRoute.Create}/:templateId?`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route
          path={`${CrudRoute.Clone}/:surveyId`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route path={`${CrudRoute.Clone}`} element={<Navigate to={`${CrudRoute.Create}`} replace />} />
        <Route element={<Navigate to="." replace />} />
      </Routes>
    </>
  );
}
```

```tsx
import * as React from 'react';
import { Navigate, Route, Routes } from 'react-router';

import { CrudRoute } from '~/Router/types';

import { ExampleForm } from './ExampleForm';
import { ExamplesHome } from './ExamplesHome';

export function ExamplePages(): React.JSX.Element | null {
  return (
    <>
      <ExamplesHome />
      <Routes>
        <Route
          path={`${CrudRoute.Edit}/:surveyId`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route
          path={`${CrudRoute.Create}/:templateId?`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route
          path={`${CrudRoute.Clone}/:surveyId`}
          element={
            <React.Suspense fallback={null}>
              <ExampleForm />
            </React.Suspense>
          }
        />
        <Route path={`${CrudRoute.Clone}`} element={<Navigate to={`${CrudRoute.Create}`} replace />} />
        <Route element={<Navigate to="." replace />} />
      </Routes>
    </>
  );
}
```

## merge imports

```tsx
import { Navigate, Route } from 'react-router';
import { Routes } from 'react-router-dom';

return (
  <Routes>
    <Route>
      <Navigate />
    </Route>
  </Routes>
);
```

```tsx
import { Navigate, Route, Routes } from 'react-router';

return (
  <Routes>
    <Route>
      <Navigate />
    </Route>
  </Routes>
);
```

## Convert Splats

```tsx
function Component() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="dashboard/*" element={<Dashboard />} />
    </Routes>
  );
}
```

```tsx
function Component() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="dashboard">
        <Route path="*" element={<Dashboard />} />
      </Route>
    </Routes>
  );
}
```

## Convert simple buildPath

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath('/setup');
}
```

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath('setup');
}
```

## Convert template string buildPath

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath(`/setup/${other}`);
}
```

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath(`setup/${other}`);
}
```

## Convert multiple buildPath

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath('/other') + buildPath(`/setup/${other}`);
}
```

```tsx
export function Component() {
  const buildPath = useRoutePathBuilder();
  return buildPath('other') + buildPath(`setup/${other}`);
}
```

## Convert unusual var name buildPath

```tsx
export function Component() {
  const p = useRoutePathBuilder();
  return p('/other') + p(`/setup/${other}`);
}
```

```tsx
export function Component() {
  const p = useRoutePathBuilder();
  return p('other') + p(`setup/${other}`);
}
```
