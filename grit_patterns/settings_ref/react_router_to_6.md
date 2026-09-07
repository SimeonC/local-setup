```grit
engine marzano(0.1)
language js


private pattern use_route_match() {
    or { function_declaration($body), arrow_function($body) } where {
        $body <: contains lexical_declaration(declarations= contains variable_declarator($name, value=contains call_expression(function=`useRouteMatch` => `useMatch`), $type)) as $lex where or {
            and {
                $name <: object_pattern(properties=$props) where or {
                    $props <: [pair_pattern(key=`path`, value=$path)],
                    and {
                        $props <: contains `path` as $path,
                        $props <: [shorthand_property_identifier_pattern()]
                    }
                },
                $lex => .,
            },
            $name <: object_pattern(properties=$props) where or {
                $props <: contains pair_pattern(key=`path`, value=$path) => .,
                $props <: contains `path` as $path => .
            },
            $path = `$name.path`
        },
        $body <: maybe contains bubble ($path) template_content(content=[template_substitution(expression=`$path`) => ., r"^/(.*)"($r) => `$r`, $...]),
        $body <: maybe contains bubble ($path) jsx_attribute(name=`path`, value=jsx_expression(expression=`$path`)) => .,
        $body <: maybe contains bubble ($path) or {
            `<Route><Redirect to={$path} /></Route>`,
            `<Route path={$path}><Redirect to={$path} /></Route>`
        } => `<Route><Redirect to="." /></Route>`
    }
}

private pattern replace_history_listener() {
    or { function_declaration($body), arrow_function($body) } where {
        $body <: contains `const $hist = useHistory()`,
        $body <: contains `React.useEffect($callback, $deps)` where {
            add_import(name="useLocation", source=`"react-router-dom"`),
        },
        $callback <: or {
            `() => $hist.listen(($loc, $act) => $effectBody)` where {
                $body <: contains `const $hist = useHistory()` as $s => `$s;
const $loc = useLocation();
const $act = useNavigationType();`,
                $deps => `[$loc, $act]`,
                add_import(name="useNavigationType", source=`"react-router-dom"`)
            },
            `() => $hist.listen(() => $effectBody)` where {
                $body <: contains `const $hist = useHistory()` as $s => `$s;
const location = useLocation();`,
                $deps => `[location]`
            },
            `() => $hist.listen(($loc) => $effectBody)` where {
                $body <: contains `const $hist = useHistory()` as $s => `$s;
const $loc = useLocation();`,
                $deps => `[$loc]`
            }
        } => `() => $effectBody`,
    }
}

private pattern mark_history_hooks() {
    `React.$use($cb, $deps)` where {
        $use <: or { `useEffect`, `useMemo`, `useCallback` },
        $deps <: `[$..., history, $...]`,
        $deps => `// TODO convert this history
    $deps`
    }
}

private pattern route_has_single_child() {
    `<Route $...>$c</Route>` where {
        $c <: not [$a],
        $c => `<>$c</>`
    }
}

function fix_route_path($path) js {
    const quotedPath = $path.text;
    const quotes = quotedPath[0];
    const path = quotedPath.slice(1, quotedPath.length - 1);
    if (path[0] === '/') return quotes + path + quotes;
    const relativePath = path.replace(/^\//gi, '');
    if (relativePath.match(/(\/|^)\:[^/:]+$/gi))
        return quotes + relativePath + quotes;
    return quotes + relativePath.replace(/\/?$/gi, '/*') + quotes;
}

predicate fix_path_props($props) {
    and {
        $props <: maybe contains jsx_attribute(name=`exact`) => .,
        $props <: maybe contains jsx_attribute(name=or { `path`, `to` }, $value) where or {
            $value <: not contains string(),
            $value <: jsx_expression(expression=call_expression()),
            $value <: contains template_string() as $template where {
                $template => fix_route_path($template)
            },
            $value => fix_route_path($value)
        }
    }
}

private pattern replace_RR_switches() {
    `<Switch>$routes</Switch>` => `<Routes>$routes</Routes>` where {
        $routes <: contains bubble `<Route $props>$children</Route>` as $route where {
            fix_path_props($props),
            or {
                $children <: [jsx_expression(expression=ternary_expression($alternative, $condition, $consequence))] where {
                    $alternative <: `null`,
                    $route => `{$condition ? <Route $props element={$consequence} /> : $alternative}`
                },
                $route => `<Route $props element={$children} />`
            }
        }
    }
}

private pattern cleanup() {
    or {
        jsx_attribute(value=jsx_expression(expression=template_string(template=template_content(content=[string_fragment() as $string]))) => `"$string"`),
        `const $_ = useHistory()` => .,
        remove_unused_imports(`"react-router-dom"`),
        remove_unused_imports(`"react-router"`)
    }
}

sequential {
    bubble file($body) where $body <: contains bubble or {
        `import { $imports } from 'react-router-dom'`,
        `import { $imports } from 'react-router'`
    } where {
        $imports <: maybe contains `useHistory` => .,
        $imports <: maybe contains `useRouteMatch` => `useMatch`,
        $imports <: maybe contains `Switch` => `Routes`,
        $imports <: maybe contains `Redirect` => `Navigate`
    },
    bubble file($body) where $body <: maybe contains bubble replace_history_listener(),
    bubble file($body) where $body <: maybe contains bubble or { function_declaration($body), arrow_function($body) } where {
        $body <: contains bubble or {
            `history.push($path)` => `void navigate($path)`,
            `history.go` => `(steps: number) => void navigate(steps)`,
            `history.go($a)` => `void navigate($a)`,
            `history.goBack` => `() => void navigate(-1)`,
            `history.goBack()` => `void navigate(-1)`,
            `history.goForward` => `() => void navigate(1)`,
            `history.goForward()` => `void navigate(1)`,
            call_expression(arguments=[$path], function=`history.replace`) => `void navigate($path, { replace: true })`,
        },
        $body <: contains `const history = useHistory()` => `const navigate = useNavigate()`,
        add_import(name="useNavigate", source=`"react-router-dom"`)
    },
    bubble file($body) where $body <: maybe contains mark_history_hooks(),
    bubble file($body) where $body <: maybe contains bubble `history.location` => `// TODO convert history
history.location`,
    bubble file($body) where $body <: maybe contains bubble use_route_match(),
    bubble file($body) where $body <: maybe contains bubble route_has_single_child(),
    bubble file($body) where $body <: maybe contains bubble replace_RR_switches(),
    bubble file($body) where $body <: maybe contains bubble `<Redirect $props />` => `<Navigate $props replace />`,
    bubble file($body) where $body <: maybe contains bubble cleanup(),
}
```

## Converts Route children to elements

```tsx
import { Redirect, Route } from 'react-router';
import { Switch } from 'react-router-dom';

function Comp() {
  return (
    <Switch>
      <Route path="some-path">
        <MyRoute />
      </Route>
      <Route path="some-path">
        {someVal}
        <MyRoute />
      </Route>
      <Route path="some-path">
        <Redirect />
      </Route>
    </Switch>
  );
}
```

```tsx
import { Navigate, Route } from 'react-router';
import { Routes } from 'react-router-dom';

function Comp() {
  return (
    <Routes>
      <Route path="some-path/*" element={<MyRoute />} />
      <Route
        path="some-path/*"
        element={
          <>
            {someVal}
            <MyRoute />
          </>
        }
      />
      <Route path="some-path/*" element={<Navigate replace />} />
    </Routes>
  );
}
```

## Removes useHistory hooks and marks places we can't convert

```tsx
import { useHistory } from 'react-router-dom';
function Component() {
  const can = usePermission();
  const buildPath = useRoutePathBuilder();
  const history = useHistory();
  const queryClient = useQueryClient();
  const compiledActions = React.useMemo(
    () =>
      actions.map(({ getAction, action, ...rest }) => ({
        ...rest,
        action:
          action ??
          getAction?.({
            item,
            can,
            queryClient,
            navigateTo: (path) => history.push(buildPath(path)),
            url: history.location.pathname,
          }) ??
          false,
      })),
    [actions, buildPath, can, history, item, queryClient],
  );
}
```

```tsx
import { useNavigate } from 'react-router-dom';

function Component() {
  const can = usePermission();
  const buildPath = useRoutePathBuilder();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const compiledActions = React.useMemo(
    () =>
      actions.map(({ getAction, action, ...rest }) => ({
        ...rest,
        action:
          action ??
          getAction?.({
            item,
            can,
            queryClient,
            navigateTo: (path) => void navigate(buildPath(path)),
            // TODO convert history
            url: history.location.pathname,
          }) ??
          false,
      })),
    // TODO convert this history
    [actions, buildPath, can, history, item, queryClient],
  );
}
```
