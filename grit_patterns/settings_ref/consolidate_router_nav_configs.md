---
title: Refactoring from nav configs and routes to consolidated Page/*/... structure
limit: apps/sample-app/src/layouts/navigation
---

As Grit can't remove files, run this shell command afterwards to delete the files we need to `find apps/sample-app/src/layouts/navigation -type f -exec grep -lz '^// DELETE grit delete file\s*$' {} + | tr '\n'
'\0' | xargs -0 git rm -f`.

Also this is very slow so should be run as `grit apply consolidate_router_nav_configs apps/sample-app/src/layouts/navigation`

In a seperate commit afterwards run the `.grit/patterns/consolidate_router_nav_configs.sh` file to shift files around.

```grit
engine marzano(0.1)
language js

predicate extract_meta($properties, $folder, $route, $route_props, $nav_config_props, $imports) {
  $folder = ``,
  $route_props = [],
  $imports = [],
  $properties <: contains pair(key=`to`, value=`'$link'`) where {
      or {
          and {
            $link <: r"/",
            $folder = `Home`,
            $subpath = `.`,
            $route_props += `layout: 'manual'`,
            $route_props += `page: ExamplePage`,
          },
          and {
            $link <: r"/account",
            $folder = `Account`,
            $subpath = `account`,
            $route_props += `layout: 'manual'`,
            $route_props += `page: Account`,
          },
          and {
              $link <: r"/legacy/(.+)"($subpath),
              to_pascal($folder, $subpath),
              $legacy_path = $subpath,
              to_kebab($subpath, $subpath),
              $route_props += `layout: 'legacy'`,
              $route_props += `legacyPath: '$legacy_path'`
          },
          and {
              $link <: r"/(.+)"($subpath),
              to_pascal($folder, $subpath),
              to_kebab($subpath, $subpath),
              $route_props += `layout: 'manual'`,
              $route_props += `page: $folder`,
              $imports += `import { $folder } from './_'`
          }
      },
  },
  $route = `$subpath`,
  $nav_config_props = [],
}

predicate handle_properties($properties, $nav_config_props, $folder) {
  $properties <: some bubble ($nav_config_props, $folder) pair() as $p where {
      or {
          $p <: `to: '$link'`,
          $p <: `type: $_`,
          $p <: `key: $_`,
          $p <: `canUpsell: $_`,
          $nav_config_props += $p
      }
  },
}

predicate write_route($folder, $route, $nav_config_props, $route_props, $imports) {
  $nav_config_props = join(list=$nav_config_props, separator=`, `),
  $route_props = join(list=$route_props, separator=`, `),
  $new_nav_config = `export const navConfig = buildNavConfig({ $nav_config_props });`,
  $root_route = `export default buildRootRoute({$route_props});`,
  if ($route <: `.`) {
    $new_file_name = `./apps/sample-app/src/screens/$folder/route.tsx`,
  } else {
    $new_file_name = `./apps/sample-app/src/screens/$folder/$route.route.tsx`,
  },
  $imports = join(list=$imports, separator=`;
`),
  $new_files += file(name = $new_file_name, body = `import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
$imports

$new_nav_config

$root_route
`)
}

multifile {
    $exports = [],
    bubble($exports) file($body) where {
      $body <: contains `export const $export: SidenavLink[] = $links_arr` where {
        $links_arr <: array(elements=$links),
        $exports += { export: `$export`, links_arr: $links_arr },
        $links <: some bubble object($properties) as $config where {
            $imports = [],
            extract_meta($properties, $folder, $route, $route_props, $nav_config_props, $imports),
            handle_properties($properties, $nav_config_props, $folder),
            write_route($folder, $route, $nav_config_props, $route_props, $imports),
        }
      },
      $body => `// DELETE grit delete file`,
    },
    file($body) where and {
      $body <: contains `export const unfilteredNavigationConfig: SidenavConfigType = $links_arr` where {
        $links_arr <: array(elements=$links),
        $links <: some bubble object($properties) as $config where {
          $properties <: contains pair(key=`type`, value=`'root-link'`),
          $properties <: contains pair(key=`key`, value=`$key`),
          $properties <: contains pair(key=`icon`, value=`$icon`),
          extract_meta($properties, $folder, $route, $route_props, $nav_config_props, imports=[]),
          handle_properties($properties, $nav_config_props, $folder),
          $imports = [`import { $icon } from '@carbon/icons-react'`],
          if ($folder <: `Home`) {
              $imports += `import { ExamplePage } from './_'`,
          } else {
              $imports += `import { Account } from './_'`,
          },
          write_route($folder, $route, $nav_config_props, $route_props, $imports),
          if ($route <: `.`) {
            $config => `navConfigToSidenavLink(groupedNavConfigs.Home.root, $key)`,
          } else {
            $config => `navConfigToSidenavLink(groupedNavConfigs['$route'].root, $key)`,
          }
        },
        $body <: contains `import { $i } from './types'` as $s where {
          $i => `RootSidenavLink, SidenavLink, $i`
        } => `$s
import { type InternalNavConfigType } from "~/Router/routeConfig";
import { groupedNavConfigs } from "~/Router/navConfigs";

function navConfigToSidenavLink({
  path,
  ...config
}: InternalNavConfigType): SidenavLink;
function navConfigToSidenavLink(
  { path, ...config }: InternalNavConfigType,
  key: string,
): RootSidenavLink;
function navConfigToSidenavLink(
  { path: p, ...config }: InternalNavConfigType,
  key?: string,
): SidenavLink | RootSidenavLink {
  const path = p as AllRoutePaths;
  if (key && config.icon)
    return {
      ...(config as RequiredKeys<InternalNavConfigType, 'icon'>),
      type: 'root-link',
      to: path,
      key,
    };
  return {
    ...config,
    type: 'link',
    to: path,
  };
}

function convertSidenavLinks(links: InternalNavConfigType[]): SidenavLink[] {
  return links.map((link) => navConfigToSidenavLink(link));
}`,
    },
    $exports <: some bubble($body) $e where {
      $export = $e.export,
      $links_arr = $e.links_arr,
      $body <: contains `import { $export } from $any` => .,
      $body <: contains `$export` where {
        $links_arr <: array(elements=$links),
        $links <: some bubble object($properties) as $config where {
            extract_meta($properties, $folder, $route, $route_props, $nav_config_props, imports=[]),
            if ($route <: `.`) {
              $config => `groupedNavConfigs.Home.root`,
            } else {
              $config => `groupedNavConfigs['$route'].root`,
            }
        }
      } => `convertSidenavLinks($links_arr)`
    }
  }
}
```

## Test

```tsx
// @filename: apps/sample-app/src/layouts/navigation/app-config.tsx
import { managementLinks } from './management';
import { resourcesLinks } from './resources';
import { type SidenavConfigType } from './types';

export const unfilteredNavigationConfig: SidenavConfigType = [
  {
    key: 'home',
    type: 'root-link',
    entity: '*',
    action: '*',
    to: '/',
    exact: true,
    labelKey: 'settings:sidenav.home',
    icon: Home,
  },
  {
    key: 'my_account',
    type: 'root-link',
    entity: '*',
    action: '*',
    to: '/account',
    exact: true,
    labelKey: 'settings:users.my_account',
    icon: User,
  },
  {
    key: 'resources',
    icon: Calendar,
    labelKey: 'settings:sidenav.resources',
    links: resourcesLinks,
  },
  {
    key: 'management',
    badge: () => {
      const badgeSize = 20;
      return (
        <ManagementBadge
          style={{
            width: badgeSize,
            maxWidth: badgeSize,
            minWidth: badgeSize,
            height: badgeSize,
            minHeight: badgeSize,
            maxHeight: badgeSize,
            padding: 0,
            display: 'inline-flex',
            justifyContent: 'center',
            alignItems: 'center',
          }}
        />
      );
    },
    labelKey: 'settings:sidenav.management',
    links: managementLinks,
  },
];

// @filename: apps/sample-app/src/layouts/navigation/resources.ts
import { type SidenavLink } from './types';

export const resourcesLinks: SidenavLink[] = [
  {
    type: 'link',
    entity: 'example_resource',
    action: 'update',
    to: '/resources',
    labelKey: 'models:example_resource',
    labelOptions: { count: 2 },
  },
  {
    type: 'link',
    entity: 'app_config',
    action: 'update',
    to: '/legacy/config',
    labelKey: 'models:app_config',
    labelOptions: { count: 2 },
  },
  {
    type: 'link',
    entity: 'component',
    action: '*',
    to: '/legacy/component',
    labelKey: 'settings:sidenav.component',
  },
];

// @filename: apps/sample-app/src/layouts/navigation/management.ts
export const managementLinks: SidenavLink[] = [
  {
    type: 'link',
    entity: 'management',
    action: '*',
    condition: ({ user }) => user.can_access_all_organizations,
    to: '/setup',
    labelKey: 'settings:sidenav.setup',
  },
  {
    type: 'link',
    entity: 'management',
    action: '*',
    canUpsell: true,
    to: '/setup/overview',
    labelKey: 'settings:sidenav.setup_dashboard',
    flag: 'setup-dashboard',
  },
  {
    type: 'link',
    entity: 'organization',
    action: 'update',
    to: '/organization',
    labelKey: 'models:organization',
    labelOptions: {
      count: 1,
    },
  },
  {
    type: 'link',
    entity: 'resource_list',
    action: 'update',
    to: '/legacy/resources',
    labelKey: 'models:resource_list',
    labelOptions: {
      count: 2,
    },
  },
];
```

```ts
// @filename: apps/sample-app/src/layouts/navigation/app-config.tsx
import { RootSidenavLink, SidenavLink, type SidenavConfigType } from './types';
import { type InternalNavConfigType } from "~/Router/routeConfig";
import { groupedNavConfigs } from "~/Router/navConfigs";

function navConfigToSidenavLink({
  path,
  ...config
}: InternalNavConfigType): SidenavLink;
function navConfigToSidenavLink(
  { path, ...config }: InternalNavConfigType,
  key: string,
): RootSidenavLink;
function navConfigToSidenavLink(
  { path: p, ...config }: InternalNavConfigType,
  key?: string,
): SidenavLink | RootSidenavLink {
  const path = p as AllRoutePaths;
  if (key && config.icon)
    return {
      ...(config as RequiredKeys<InternalNavConfigType, 'icon'>),
      type: 'root-link',
      to: path,
      key,
    };
  return {
    ...config,
    type: 'link',
    to: path,
  };
}

function convertSidenavLinks(links: InternalNavConfigType[]): SidenavLink[] {
  return links.map((link) => navConfigToSidenavLink(link));
}

export const unfilteredNavigationConfig: SidenavConfigType = [navConfigToSidenavLink(groupedNavConfigs.Home.root, 'home'), navConfigToSidenavLink(groupedNavConfigs['account'].root, 'my_account'),
  {
    key: 'resources',
    icon: Calendar,
    labelKey: 'settings:sidenav.resources',
    links: convertSidenavLinks([
      groupedNavConfigs['resources'].root,
      groupedNavConfigs['app-config'].root,
      groupedNavConfigs['component'].root,
    ]),
  },
  {
    key: 'management',
    badge: () => {
      const badgeSize = 20;
      return (
        <ManagementBadge
          style={{
            width: badgeSize,
            maxWidth: badgeSize,
            minWidth: badgeSize,
            height: badgeSize,
            minHeight: badgeSize,
            maxHeight: badgeSize,
            padding: 0,
            display: 'inline-flex',
            justifyContent: 'center',
            alignItems: 'center',
          }}
        />
      );
    },
    labelKey: 'settings:sidenav.management',
    links: convertSidenavLinks([
      groupedNavConfigs['setup'].root,
      groupedNavConfigs['setup-dashboard'].root,
      groupedNavConfigs['organization'].root,
      groupedNavConfigs['resource-lists'].root,
    ]),
  },];
// @filename: apps/sample-app/src/layouts/navigation/resources.ts
// DELETE grit delete file
// @filename: apps/sample-app/src/layouts/navigation/management.ts
// DELETE grit delete file
// @filename: ./apps/sample-app/src/screens/Home/route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { Home } from '@carbon/icons-react';
import { ExamplePage } from './_';

export const navConfig = buildNavConfig({
  entity: '*',
  action: '*',
  exact: true,
  labelKey: 'settings:sidenav.home',
  icon: Home,
});

export default buildRootRoute({ layout: 'manual', page: ExamplePage });
// @filename: ./apps/sample-app/src/screens/Account/account.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { User } from '@carbon/icons-react';
import { Account } from './_';

export const navConfig = buildNavConfig({
  entity: '*',
  action: '*',
  exact: true,
  labelKey: 'settings:users.my_account',
  icon: User,
});

export default buildRootRoute({ layout: 'manual', page: Account });
// @filename: ./apps/sample-app/src/screens/Organization/organization.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { Organization } from './_';

export const navConfig = buildNavConfig({
  entity: 'organization',
  action: 'update',
  labelKey: 'models:organization',
  labelOptions: {
    count: 1,
  },
});

export default buildRootRoute({ layout: 'manual', page: Organization });
// @filename: ./apps/sample-app/src/screens/Setup/setup.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { Setup } from './_';

export const navConfig = buildNavConfig({
  entity: 'management',
  action: '*',
  condition: ({ user }) => user.can_access_all_organizations,
  labelKey: 'settings:sidenav.setup',
});

export default buildRootRoute({ layout: 'manual', page: Setup });
// @filename: ./apps/sample-app/src/screens/SetupDashboard/setup/overview.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { SetupDashboard } from './_';

export const navConfig = buildNavConfig({
  entity: 'management',
  action: '*',
  labelKey: 'settings:sidenav.setup_dashboard',
  flag: 'setup-dashboard',
});

export default buildRootRoute({ layout: 'manual', page: SetupDashboard });
// @filename: ./apps/sample-app/src/screens/ResourceLists/resource-lists.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';

export const navConfig = buildNavConfig({
  entity: 'resource_list',
  action: 'update',
  labelKey: 'models:resource_list',
  labelOptions: {
    count: 2,
  },
});

export default buildRootRoute({ layout: 'legacy', legacyPath: 'resource_lists' });
// @filename: ./apps/sample-app/src/screens/ExampleResources/resources.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';
import { ExampleResources } from './_';

export const navConfig = buildNavConfig({
  entity: 'example_resource',
  action: 'update',
  labelKey: 'models:example_resource',
  labelOptions: { count: 2 },
});

export default buildRootRoute({ layout: 'manual', page: ExampleResources });
// @filename: ./apps/sample-app/src/screens/AppConfig/app-config.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';

export const navConfig = buildNavConfig({
  entity: 'app_config',
  action: 'update',
  labelKey: 'models:app_config',
  labelOptions: { count: 2 },
});

export default buildRootRoute({ layout: 'legacy', legacyPath: 'app_config' });
// @filename: ./apps/sample-app/src/screens/Component/component.route.tsx
import { buildRootRoute, buildNavConfig } from '~/Router/routeConfig';

export const navConfig = buildNavConfig({
  entity: 'component',
  action: '*',
  labelKey: 'settings:sidenav.component',
});

export default buildRootRoute({ layout: 'legacy', legacyPath: 'component' });
```
