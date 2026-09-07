#!/bin/bash
# To run this script do the following two commands; (grit_auto just runs each pattern, then nx quality format and prettier, then commits each step)
# `grit_auto react_router_to_6 react_router_to_7 remove_crud_route_enum consolidate_router_nav_configs consolidate_router_imports move_router_types_to_lib`
# `sh .grit/patterns/consolidate_router_nav_configs.sh`

rm -rf ./apps/sample-app/src/screens
git reset --hard

pushd ./apps/sample-app/src/screens > /dev/null || exit

find . -name "*.route.tsx" | while read file; do
    dir=$(dirname "$file")
    filename=$(basename "$file")
    base=$(basename "$file" .route.tsx)
    current=$(basename "$dir")
    if [ "$current" != "$base" ]; then
        parent=$(dirname "$dir")
        rm -rf "$parent/$base/_"

        if [ "$(echo "$current" | tr '[:upper:]' '[:lower:]')" = "$(echo "$base" | tr '[:upper:]' '[:lower:]')" ]; then
            tmp_name="${base}_tmp"
            mkdir -p "$parent/$tmp_name"
            git mv "$dir/"* "$parent/$tmp_name/"
            rm -rf "$dir"
            mkdir -p "$parent/$base/_"
            git mv "$parent/$tmp_name/"* "$parent/$base/_/"
            rmdir "$parent/$tmp_name"
        else
            mkdir -p "$parent/$base/_"
            git mv "$dir/"* "$parent/$base/_/"
            rm -rf "$dir"
        fi
        git mv "$parent/$base/_/$filename" "$parent/$base/route.tsx"
    else
        git mv "$file" "$dir/route.tsx"
    fi
done

mkdir -p examples/_
git mv Example/* examples/_/
rmdir Example
mkdir -p Home/_
git mv Home/Home.cy.tsx Home/_/Home.cy.tsx
git mv Home/index.tsx Home/_/index.tsx

popd > /dev/null

echo "Committing changes..."
git add .
git commit -m "🚧 run .grit/patterns/consolidate_router_nav_configs.sh [clean up route movements]" --no-verify

echo ""
echo "🚚 Moving pages to nx projects..."
echo ""

mkdir -p ./output

find ./apps/sample-app/src/screens -type d -mindepth 1 -maxdepth 1 | while read dir; do
    page_name=$(basename "$dir")
    mkdir -p "./output/$page_name/src"

    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        # Move files while preserving directory structure
        find "$dir" -type f | while read file; do
            # Get the relative path from the source directory
            rel_path="${file#$dir/}"
            # Create the destination directory structure
            dest_dir="./output/$page_name/src/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            # Move the file to the correct location
            git mv "$file" "$dest_dir/"
        done
        # Remove empty directories after moving files
        find "$dir" -type d -empty -delete
    fi

    # Create configuration files for each page
    page_dir="./output/$page_name"

    # .eslintrc.cjs
    cat > "$page_dir/.eslintrc.cjs" << 'EOF'
module.exports = {
  extends: ['@example-org/eslint-config/typescript'],
  parserOptions: {
    project: ['tsconfig.json', 'tsconfig.*?.json'],
  },
  settings: {
    'import/resolver': {
      typescript: {
        project: ['tsconfig.json', 'tsconfig.*?.json'],
      },
    },
  },
};
EOF

    # project.json
    cat > "$page_dir/project.json" << EOF
{
  "name": "$page_name",
  "\$schema": "../../node_modules/nx/schemas/project-schema.json",
  "sourceRoot": "output/$page_name/src",
  "projectType": "library",
  "targets": {
    "quality": {},
    "typecheck": {
      "options": {
        "tsConfigs": ["tsconfig.lib.json"]
      }
    },
    "unit-test": {
      "executor": "@nx/vite:test",
      "outputs": ["{options.reportsDirectory}"],
      "options": {
        "passWithNoTests": true,
        "reportsDirectory": "../../junit/output/$page_name"
      }
    }
  },
  "tags": []
}
EOF

    # tsconfig.json
    cat > "$page_dir/tsconfig.json" << 'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "forceConsistentCasingInFileNames": true,
    "strict": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  },
  "files": [],
  "include": [],
  "references": [
    {
      "path": "./tsconfig.lib.json"
    }
  ]
}
EOF

    # tsconfig.lib.json
    cat > "$page_dir/tsconfig.lib.json" << 'EOF'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "outDir": "../../dist/out-tsc",
    "declaration": true,
    "types": [
      "node",
      "vite/client",
      "vitest/importMeta",
      "workspace-definitions"
    ],
    "paths": {
      "#cypress/*": ["apps/sample-app/cypress/*"],
      "@app/translation": ["libs/app/i18n/src/index.ts"],
      "@app/translation-test": ["libs/app/i18n/src/testIndex.ts"],
      "@components/status-badge": ["libs/components/status-badge/src/index.ts"],
      "@local/api": ["libs/api/src/index.ts"],
      "@local/models": ["libs/models/src/index.ts"],
      "@local/router": ["libs/router/src/index.ts"],
      "@local/type-utils": ["libs/type-utils/src/index.ts"],
      "@local/vite-plugins": ["libs/vite-plugins/src/index.ts"],
      "~/*": ["apps/sample-app/src/*"]
    }
  },
  "include": ["src/**/*.ts", "../../env.d.ts"],
  "exclude": ["jest.config.ts", "src/**/*.spec.ts", "src/**/*.test.ts"]
}
EOF

    # vite.config.ts
    cat > "$page_dir/vite.config.ts" << EOF
// eslint-disable-next-line eslint-comments/disable-enable-pair
/* eslint-disable no-console */
import { defineConfig } from 'vite';
import tsconfigPaths from 'vite-tsconfig-paths';

// eslint-disable-next-line import/no-default-export
export default defineConfig(() => ({
  plugins: [tsconfigPaths()],
  cacheDir: '../../node_modules/.vitest',
  test: {
    environment: 'jsdom',
    include: ['src/**/*.{test,spec}.{ts,tsx}', 'src/**/*(!.cy).{ts,tsx}'],
    includeSource: ['src/**/*.{ts,tsx}'],
    reporters: process.env.CI ? ['default', 'junit'] : ['default'],
    outputFile: '../../junit/output/$page_name/test.xml',
  },
}));
EOF

    # tsconfig.cypress-ct.json
    cat > "$page_dir/tsconfig.cypress-ct.json" << 'EOF'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "outDir": "../../dist/out-tsc",
    "declaration": true,
    "types": ["node", "workspace-definitions"],
    "jsx": "react-jsx",
    "jsxImportSource": "@emotion/react",
    "paths": {
      "#cypress/*": ["apps/sample-app/cypress/*"],
      "@app/translation": ["libs/app/i18n/src/index.ts"],
      "@app/translation-test": ["libs/app/i18n/src/testIndex.ts"],
      "@components/status-badge": ["libs/components/status-badge/src/index.ts"],
      "@local/api": ["libs/api/src/index.ts"],
      "@local/models": ["libs/models/src/index.ts"],
      "@local/router": ["libs/router/src/index.ts"],
      "@local/type-utils": ["libs/type-utils/src/index.ts"],
      "@local/vite-plugins": ["libs/vite-plugins/src/index.ts"],
      "~/*": ["apps/sample-app/src/*"]
    }
  },
  "include": ["src/**/*.cy.ts", "src/**/*.cy.tsx", "../../env.d.ts"],
  "files": ["../../apps/sample-app/cypress/support/component.tsx"]
}
EOF
done

rmdir ./apps/sample-app/src/screens


echo "Committing changes..."
git add .
git commit -m "🚧 run .grit/patterns/consolidate_router_nav_configs.sh [move pages to nx projects]" --no-verify

npx grit check --fix
npx nx run-many -t quality -c format
npx prettier -w . --log-level=error
git add .
git commit -m "🚧 run .grit/patterns/consolidate_router_nav_configs.sh [fix linting and formatting]" --no-verify