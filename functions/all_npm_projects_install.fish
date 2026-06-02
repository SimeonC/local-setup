function all_npm_projects_install
  set -g dry_run false
  set -g dependency ""
  set -g base_dir ~/Development
  set -g install_locations
  set -g workspace_roots_to_update

  # Parse arguments
  for arg in $argv
    if test "$arg" = "--dry-run"
      set dry_run true
    else
      set dependency $arg
    end
  end

  if test -z "$dependency"
    echo (set_color --bold yellow)"📋 Usage:"(set_color normal)
    echo "  all_npm_projects_install [--dry-run] [dependency]"
    echo (set_color cyan)"🔍 Example:"(set_color normal)
    echo "  all_npm_projects_install @tablecheck/tablekit-locale-selector@1.2.5"
    echo (set_color cyan)"🛠 Options:"(set_color normal)
    echo "  --dry-run    Show what would be installed without actually installing"
    return 1
  end

  # Verify that a version is specified
  if string match -q "@*/*@*" $dependency
    # This is a scoped package with version
    set dependency_name (echo $dependency | sed -E 's/(@[^/]+\/[^@]+)@.*/\1/')
  else if string match -q "*@*" $dependency
    # Non-scoped package with version (like package@1.2.3)
    set dependency_name (echo $dependency | sed -E 's/([^@]+)@.*/\1/')
  else
    # No version specified
    echo (set_color --bold red)"⚠️ Error: Version must be specified in the dependency argument"(set_color normal)
    echo (set_color cyan)"🔍 Example:"(set_color normal)
    echo "  all_npm_projects_install @tablecheck/tablekit-locale-selector@1.2.5"
    return 1
  end

  echo (set_color --bold)"🔎 Searching for projects using"(set_color --bold blue) $dependency_name(set_color normal)

  set found_count 0

  function perform_install
    set -l project_dir $argv[1]
    set -l package_path $argv[2]
    set -l use_legacy $argv[3]
    set -l pm $argv[4]
    set -l install_status 0

    # Create relative path from the Development folder
    set -l rel_project_dir (string replace "$base_dir/" "" "$project_dir")

    pushd $project_dir

    # If it's a sub-package in a workspace, use workspace flag
    if test "$package_path" != "."
      set relative_path (string replace "$project_dir/" "" "$package_path")

      if test "$dry_run" = "true"
        switch $pm
          case pnpm
            echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "pnpm --filter $relative_path add $dependency"(set_color normal)
          case bun
            echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "bun add (in $relative_path)"(set_color normal)
          case '*'
            if test "$use_legacy" = "true"
              echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "npm install -w $relative_path $dependency --legacy-peer-deps"(set_color normal)
            else
              echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "npm install -w $relative_path $dependency"(set_color normal)
            end
        end
        set install_status 0
        set -ga install_locations "$rel_project_dir ($relative_path)"
      else
        switch $pm
          case pnpm
            echo (set_color magenta)"📦 Installing with pnpm --filter..."(set_color normal)
            pnpm --filter $relative_path add $dependency
            set install_status $status
          case bun
            # bun workspace add not well supported; fall back to npm
            echo (set_color magenta)"📦 Installing with npm workspace (bun fallback)..."(set_color normal)
            npm install -w $relative_path $dependency
            set install_status $status
          case '*'
            if test "$use_legacy" = "true"
              echo (set_color magenta)"📦 Installing with -w and --legacy-peer-deps..."(set_color normal)
              npm install -w $relative_path $dependency --legacy-peer-deps
              set install_status $status
            else
              echo (set_color magenta)"📦 Installing with -w..."(set_color normal)
              npm install -w $relative_path $dependency
              set install_status $status
            end
        end

        if test $install_status -eq 0
          set -ga install_locations "$rel_project_dir ($relative_path)"
        end
      end
    else
      # Regular install at root level
      if test "$dry_run" = "true"
        switch $pm
          case pnpm
            echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "pnpm add $dependency"(set_color normal)
          case bun
            echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "bun add $dependency"(set_color normal)
          case '*'
            if test "$use_legacy" = "true"
              echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "npm install $dependency --legacy-peer-deps"(set_color normal)
            else
              echo (set_color cyan)"🧪 Would install with:"(set_color yellow) "npm install $dependency"(set_color normal)
            end
        end
        set install_status 0
        set -ga install_locations "$rel_project_dir"
      else
        switch $pm
          case pnpm
            echo (set_color magenta)"📦 Installing with pnpm..."(set_color normal)
            pnpm add $dependency
            set install_status $status
          case bun
            echo (set_color magenta)"📦 Installing with bun..."(set_color normal)
            bun add $dependency
            set install_status $status
          case '*'
            if test "$use_legacy" = "true"
              echo (set_color magenta)"📦 Installing with --legacy-peer-deps..."(set_color normal)
              npm install $dependency --legacy-peer-deps
              set install_status $status
            else
              echo (set_color magenta)"📦 Installing..."(set_color normal)
              npm install $dependency
              set install_status $status
            end
        end

        if test $install_status -eq 0
          set -ga install_locations "$rel_project_dir"
        end
      end
    end

    popd
    return $install_status
  end

  function add_legacy_peer_deps_to_npmrc
    set -l project_root $argv[1]
    set -l npmrc_path "$project_root/.npmrc"
    set -l modified false

    if test "$dry_run" != "true"
      echo (set_color cyan)"🔧 Checking for .npmrc in"(set_color yellow) "$project_root"(set_color normal)
    end

    if test -f $npmrc_path
      # Check if legacy-peer-deps is already set
      if grep -q "legacy-peer-deps=true" $npmrc_path
        if test "$dry_run" != "true"
          echo (set_color green)"✓ .npmrc already has legacy-peer-deps=true"(set_color normal)
        end
        return 0
      else
        if test "$dry_run" = "true"
          echo (set_color cyan)"🧪 Would add"(set_color yellow) "legacy-peer-deps=true"(set_color cyan) "to existing .npmrc if normal install failed and legacy-peer-deps passed"(set_color normal)
        else
          echo (set_color magenta)"📝 Adding legacy-peer-deps=true to existing .npmrc..."(set_color normal)
          echo "legacy-peer-deps=true" >> $npmrc_path
          echo (set_color green)"✓ Added legacy-peer-deps=true to .npmrc"(set_color normal)
        end
        set modified true
      end
    else
      if test "$dry_run" = "true"
        echo (set_color cyan)"🧪 Would create new .npmrc with"(set_color yellow) "legacy-peer-deps=true if normal install failed and legacy-peer-deps passed"(set_color normal)
      else
        echo (set_color magenta)"📝 Creating new .npmrc with legacy-peer-deps=true..."(set_color normal)
        echo "legacy-peer-deps=true" > $npmrc_path
        echo (set_color green)"✓ Created .npmrc with legacy-peer-deps=true"(set_color normal)
      end
      set modified true
    end

    if test "$modified" = "true"
      set -l rel_project_dir (string replace "$base_dir/" "" "$project_root")
      return 0
    end

    return 1
  end

  # Get direct children of Development directory
  set project_dirs (find $base_dir -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  set pkg_files ""

  echo (set_color cyan)"📋 Found"(set_color --bold yellow) (count $project_dirs)(set_color cyan) "projects to check"(set_color normal)

  # For each project directory, find package.json files
  for project_dir in $project_dirs
    set project_name (basename $project_dir)
    echo (set_color cyan)"🔍 Checking"(set_color --bold) $project_name(set_color normal)

    # Check if it's a git repository (handles both regular repos and worktrees)
    if _is_git_repo $project_dir
      # Use git ls-files to respect .gitignore
      pushd $project_dir
      set git_pkg_files (git ls-files --cached --others --exclude-standard "**/package.json" "package.json" 2>/dev/null)

      # Convert relative paths to absolute
      for rel_file in $git_pkg_files
        set -a pkg_files "$project_dir/$rel_file"
      end
      popd
    else
      # If not a git repo, use find but limit depth
      set found_files (find $project_dir -name "package.json" -type f -not -path "*/node_modules/*" -not -path "*/\.*/*" 2>/dev/null)
      set pkg_files $pkg_files $found_files
    end
  end

  echo (set_color cyan)"📋 Found"(set_color --bold yellow) (count $pkg_files)(set_color cyan) "package.json files to check"(set_color normal)

  # Track workspace roots and their subpackages with the dependency
  set -g workspace_dependency_map

  for pkg_file in $pkg_files
    set dir_path (dirname $pkg_file)
    set rel_dir_path (string replace "$base_dir/" "~/Development/" "$dir_path")

    # Check if this package.json contains the dependency using jq
    set has_dependency (jq --arg dep "$dependency_name" '.dependencies[$dep] // .devDependencies[$dep] // .peerDependencies[$dep] // empty' $pkg_file 2>/dev/null)

    if test -n "$has_dependency"
      set current_dep_version (jq --arg dep "$dependency_name" '(.dependencies[$dep] // .devDependencies[$dep] // .peerDependencies[$dep])' $pkg_file 2>/dev/null | tr -d '"')

      # Skip non-semver dependencies (file://, github://, etc.)
      if string match -q "file:*" "$current_dep_version" || string match -q "github:*" "$current_dep_version" || string match -q "git+*" "$current_dep_version" || string match -q "http*" "$current_dep_version"
        echo (set_color yellow)"🔗 Skipping non-semver dependency"(set_color cyan) $current_dep_version(set_color yellow)" in"(set_color --underline) $rel_dir_path(set_color normal)
        continue
      end

      set found_count (math $found_count + 1)
      echo (set_color green)"🧩 [$found_count] Found dependency"(set_color cyan) $current_dep_version(set_color green)" in"(set_color --underline) $rel_dir_path(set_color normal)

      # Check if this project uses workspaces with jq
      set has_workspaces (jq 'has("workspaces")' $pkg_file 2>/dev/null)

      # Determine if this is a workspace root or a sub-package
      set project_root $dir_path
      set package_path "."

      if test "$has_workspaces" = "false"
        # Check if this might be a sub-package in a workspace
        set parent_dir $dir_path
        set found_workspace false

        # Look up to find workspace root (max 5 levels up)
        for i in (seq 1 5)
          set parent_dir (dirname $parent_dir)
          set workspace_pkg "$parent_dir/package.json"

          if test -f $workspace_pkg
            set workspace_has_workspaces (jq 'has("workspaces")' $workspace_pkg 2>/dev/null)
            if test "$workspace_has_workspaces" = "true"
              set project_root $parent_dir
              set package_path $dir_path
              set found_workspace true

              # Add this package to the workspace dependency map
              set workspace_key "$parent_dir"
              set workspace_subpackage "$dir_path"

              # Check if we've already seen this workspace root
              set idx (contains -i -- "$workspace_key" $workspace_dependency_map)
              if test -z "$idx"
                # First time seeing this workspace root with a package that has the dependency
                set -a workspace_dependency_map "$workspace_key" "$workspace_subpackage"
              else
                # We've seen this workspace root before, add the subpackage
                set next_idx (math $idx + 1)
                set existing_packages $workspace_dependency_map[$next_idx]
                set workspace_dependency_map[$next_idx] "$existing_packages:$workspace_subpackage"
              end

              break
            end
          end

          # Stop if we reach the home directory or Development directory
          if test "$parent_dir" = "$HOME" -o "$parent_dir" = "$base_dir"
            break
          end
        end
      else
        # This is a workspace root, check if we need to add it
        set workspace_key "$dir_path"
        set idx (contains -i -- "$workspace_key" $workspace_dependency_map)
        if test -z "$idx"
          # First time seeing this workspace root with the dependency
          set -a workspace_dependency_map "$workspace_key" ""
        end
      end

      # Detect PM for this project root to drive install and retry logic
      set -l pm (_pm_detect $project_root)

      if test "$dry_run" = "true"
        perform_install $project_root $package_path "false" $pm
        # Only show legacy-peer-deps warning for npm repos
        if test "$pm" = npm
          add_legacy_peer_deps_to_npmrc $project_root
        end
      else
        # Try installing first
        perform_install $project_root $package_path "false" $pm
        set install_status $status

        # Retry with --legacy-peer-deps only applies to npm repos
        if test $install_status -ne 0; and test "$pm" = npm
          echo (set_color yellow)"⚠️ Initial install failed, retrying with --legacy-peer-deps..."(set_color normal)
          perform_install $project_root $package_path "true" $pm
          set install_status $status

          # If legacy peer deps worked, add it to .npmrc
          if test $install_status -eq 0
            echo (set_color yellow)"⚠️ Project requires legacy peer deps. Updating .npmrc..."(set_color normal)
            add_legacy_peer_deps_to_npmrc $project_root
          end
        end
      end
    end
  end

  # Check for workspace roots that need an additional install
  for i in (seq 1 2 (count $workspace_dependency_map))
    set workspace_root $workspace_dependency_map[$i]
    set subpackages $workspace_dependency_map[(math $i + 1)]

    # If both the workspace root and at least one subpackage have the dependency
    if test -n "$subpackages" && contains "$workspace_root" $install_locations
      set rel_workspace_root (string replace "$base_dir/" "" "$workspace_root")
      set -l ws_pm (_pm_detect $workspace_root)

      if test "$dry_run" = "true"
        echo (set_color cyan)"🧪 Would run"(set_color yellow) "$ws_pm install"(set_color cyan) "at workspace root:"(set_color normal) "~/Development/$rel_workspace_root"
        echo (set_color cyan)"   (Both workspace root and subpackage(s) have the dependency)"(set_color normal)
      else
        echo (set_color magenta)"📦 Running $ws_pm install at workspace root:"(set_color normal) "~/Development/$rel_workspace_root"
        echo (set_color magenta)"   (Both workspace root and subpackage(s) have the dependency)"(set_color normal)

        pushd $workspace_root
        _pm_run i
        popd
      end
    end
  end

  if test $found_count -eq 0
      echo (set_color yellow)"🔍 No projects found using"(set_color --bold) $dependency_name(set_color normal)
  else
    if test "$dry_run" = "true"
      echo (set_color --bold cyan)"🧪 Would install"(set_color --bold blue) $dependency(set_color --bold cyan) "in the following locations:"(set_color normal)
    else
      echo (set_color --bold green)"✅ Finished installing"(set_color --bold blue) $dependency(set_color --bold green) "in the following locations:"(set_color normal)
    end

    if test (count $install_locations) -eq 0
      echo (set_color red)"❌ No successful installations"(set_color normal)
    else
      for location in $install_locations
        # Format with tilde prefix for better readability
        set formatted_location (string replace -r "^" "~/Development/" $location)
        echo (set_color green)"✓"(set_color normal) $formatted_location
      end
    end
  end
end
