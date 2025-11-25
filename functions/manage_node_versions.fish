function manage_node_versions --description 'Scan development projects and manage Node.js versions with asdf'
    # Set up signal handling for clean exit
    function _cleanup_on_signal
        echo ""
        echo "🛑 Operation cancelled by user"
        return 130
    end

    # Trap SIGINT (Ctrl+C)
    trap '_cleanup_on_signal' INT

    echo "🔍 Searching for Node.js version files in ~/Development/..."

    set -l found_versions
    set -l dev_dir "$HOME/Development"

    # Array to track which projects use which versions and their file paths
    set -l version_projects
    set -l version_files

    if not test -d $dev_dir
        echo "❌ Development directory not found: $dev_dir"
        return 1
    end

    echo "📄 Scanning projects for version specification files..."
    echo ""

    # Iterate through each project directory
    for project_dir in $dev_dir/*/
        if test -d $project_dir
            set -l project_name (basename $project_dir)

            set -l project_versions_found 0

            # Check if this is a git repository
            set -l is_git_repo 0
            if test -d $project_dir/.git
                set is_git_repo 1
            end

            # Search for .nvmrc files in this project
            set -l nvmrc_files
            if test $is_git_repo -eq 1
                # Use git ls-files to respect .gitignore
                pushd $project_dir
                for relative_file in (git ls-files | grep -E '\.nvmrc$')
                    set -a nvmrc_files "$project_dir/$relative_file"
                end
                popd
            else
                # Use find with common ignore patterns for non-git projects
                set nvmrc_files (find $project_dir -name ".nvmrc" -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.next/*" -not -path "*/.cache/*" 2>/dev/null)
            end

            # Check for interruption after file search
            if test $status -eq 130
                _cleanup_on_signal
                return 130
            end

            for file in $nvmrc_files
                if test -f $file
                    set -l node_ver (cat $file | string trim)
                    # Only add non-empty versions
                    if test -n "$node_ver" -a "$node_ver" != ""
                        # Strip 'v' prefix if present (normalize for asdf)
                        set -l normalized_ver (echo $node_ver | string replace -r '^v' '')
                        set -l relative_path (string replace $project_dir "" $file)
                        set -l full_relative_path "$project_name$relative_path"
                        set -a found_versions $normalized_ver
                        set -a version_projects "$normalized_ver|$project_name"
                        set -a version_files "$normalized_ver|$full_relative_path"
                        set project_versions_found (math $project_versions_found + 1)
                    end
                end
            end

            # Search for .tool-versions files in this project
            set -l tool_version_files
            if test $is_git_repo -eq 1
                # Use git ls-files to respect .gitignore
                pushd $project_dir
                for relative_file in (git ls-files | grep -E '\.tool-versions$')
                    set -a tool_version_files "$project_dir/$relative_file"
                end
                popd
            else
                # Use find with common ignore patterns for non-git projects
                set tool_version_files (find $project_dir -name ".tool-versions" -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.next/*" -not -path "*/.cache/*" 2>/dev/null)
            end

            # Check for interruption after file search
            if test $status -eq 130
                _cleanup_on_signal
                return 130
            end

            for file in $tool_version_files
                if test -f $file
                    set -l nodejs_line (grep "^nodejs " $file 2>/dev/null)
                    if test -n "$nodejs_line"
                        set -l node_ver (echo $nodejs_line | awk '{print $2}' | string trim)
                        # Only add non-empty versions
                        if test -n "$node_ver" -a "$node_ver" != ""
                            # Strip 'v' prefix if present (normalize for asdf)
                            set -l normalized_ver (echo $node_ver | string replace -r '^v' '')
                            set -l relative_path (string replace $project_dir "" $file)
                            set -l full_relative_path "$project_name$relative_path"
                            set -a found_versions $normalized_ver
                            set -a version_projects "$normalized_ver|$project_name"
                            set -a version_files "$normalized_ver|$full_relative_path"
                            set project_versions_found (math $project_versions_found + 1)
                        end
                    end
                end
            end
        end
    end

    # Remove duplicates and sort versions, filtering out empty ones
    set -l unique_versions
    for ver in $found_versions
        if test -n "$ver" -a "$ver" != ""
            set -a unique_versions $ver
        end
    end
    set unique_versions (printf '%s\n' $unique_versions | sort -u)

    # Clean unique versions (remove any trailing whitespace) and update version_files accordingly
    set -l clean_unique_versions
    set -l clean_version_files
    for ver in $unique_versions
        set -l clean_ver (echo $ver | string trim)
        if test -n "$clean_ver"
            set -a clean_unique_versions $clean_ver

            # Update version_files entries to use cleaned version
            for entry in $version_files
                set -l version_part (string split "|" $entry)[1]
                set -l file_part (string split "|" $entry)[2]
                set -l clean_version_part (echo $version_part | string trim)
                if test "$clean_version_part" = "$clean_ver"
                    set -a clean_version_files "$clean_ver|$file_part"
                end
            end
        end
    end
    set unique_versions $clean_unique_versions
    set version_files $clean_version_files

    if test (count $unique_versions) -eq 0
        echo "❌ No Node.js versions found in any projects"
        return 1
    end

    echo "🎯 Summary - Unique Node.js versions found: "(count $unique_versions)
    echo ""
    for node_ver in $unique_versions
        echo "  • $node_ver"
        # Show which files use this version
        echo "    📁 Found in:"
        set -l files_for_version
        for entry in $version_files
            set -l version_part (string split "|" $entry)[1]
            set -l file_part (string split "|" $entry)[2]
            if test "$version_part" = "$node_ver"
                set -a files_for_version $file_part
            end
        end
        set -l unique_files (printf '%s\n' $files_for_version | sort -u)
        for file_path in $unique_files
            echo "       $file_path"
        end
        echo ""
    end

    echo ""
    echo "🔍 Checking currently installed Node.js versions with asdf..."
    set -l installed_versions (asdf list nodejs 2>/dev/null | string trim)

    echo "📦 Currently installed versions:"
    if test (count $installed_versions) -eq 0
        echo "  • None"
    else
        for installed_ver in $installed_versions
            echo "  • $installed_ver"
        end
    end

    # Clean installed versions (remove asterisks and whitespace)
    set -l clean_installed_versions
    for installed_version in $installed_versions
        set -l clean_version (echo $installed_version | string replace -r '\s*\*?\s*' '' | string trim)
        if test -n "$clean_version"
            set -a clean_installed_versions $clean_version
        end
    end

    # Build lists of versions to install and uninstall
    set -l to_install
    set -l to_uninstall

    # Find versions that need to be installed
    for needed_version in $unique_versions
        set -l is_installed 0
        for clean_installed in $clean_installed_versions
            if test "$needed_version" = "$clean_installed"
                set is_installed 1
                break
            end
        end
        if test $is_installed -eq 0
            set -a to_install $needed_version
        end
    end

    # Find versions that can be uninstalled (installed but not needed)
    for clean_installed in $clean_installed_versions
        set -l is_needed 0
        for needed_version in $unique_versions
            if test "$clean_installed" = "$needed_version"
                set is_needed 1
                break
            end
        end
        if test $is_needed -eq 0
            set -a to_uninstall $clean_installed
        end
    end

    if test (count $to_install) -eq 0 -a (count $to_uninstall) -eq 0
        echo "✅ All required versions are already installed and no unused versions found!"
        echo "🎉 Nothing to do!"
        return 0
    end

    # Build options for Gum selection
    set -l gum_options
    set -l action_types

    # Add install options
    for ver in $to_install
        # Get file paths for this version
        set -l file_paths
        for entry in $version_files
            set -l version_part (string split "|" $entry)[1]
            set -l file_part (string split "|" $entry)[2]
            if test "$version_part" = "$ver"
                set -a file_paths $file_part
            end
        end

        # Clean up file paths for display (remove extensions and deduplicate)
        set -l cleaned_paths
        for file_path in $file_paths
            # Remove /.nvmrc and /.tool-versions extensions for display
            set -l clean_path (echo $file_path | string replace -r '/\.nvmrc$' '' | string replace -r '/\.tool-versions$' '')
            set -a cleaned_paths $clean_path
        end

        # Remove duplicates and sort
        set -l unique_display_paths (printf '%s\n' $cleaned_paths | sort -u)
        set -l files_display (string join ", " $unique_display_paths)

        set -a gum_options "📥 Install Node.js $ver ($files_display)"
        set -a action_types "install:$ver"
    end

    # Add uninstall options
    for ver in $to_uninstall
        set -a gum_options "🗑️  Uninstall Node.js $ver (unused)"
        set -a action_types "uninstall:$ver"
    end

    # Early exit option using Gum
    echo ""
    if not gum confirm --default=true "🤔 Would you like to see the interactive selection menu?"
        echo "👋 Exiting without making changes."
        return 0
    end

    # Use Gum for multi-select checkbox interface
    echo ""
    echo "🎛️  Select operations to perform:"

    set -l selected_options (printf '%s\n' $gum_options | gum choose --no-limit --header "Use space to select/deselect, enter to proceed")

    if test (count $selected_options) -eq 0
        echo "👋 No operations selected, exiting."
        return 0
    end

    # Convert selected options to actions by finding their indices
    set -l selected_actions
    for selected_option in $selected_options
        for i in (seq 1 (count $gum_options))
            if test "$gum_options[$i]" = "$selected_option"
                set -a selected_actions $action_types[$i]
                break
            end
        end
    end

    # Final confirmation
    echo ""
    echo "📋 Selected operations:"
    for selected_option in $selected_options
        echo "  • $selected_option"
    end

    echo ""
    if not gum confirm --default=false "⚠️  Proceed with these operations?"
        echo "👋 Operations cancelled."
        return 0
    end

    echo ""
    echo "🧹 Executing selected operations..."

    # Execute selected operations
    set -l current_operation 1
    set -l total_operations (count $selected_actions)

    for action in $selected_actions
        set -l action_type (string split ":" $action)[1]
        set -l ver (string split ":" $action)[2]

        if test "$action_type" = "install"
            echo ""
            echo "⬇️  Installing Node.js $ver... ($current_operation/$total_operations)"

            asdf install nodejs $ver
            set -l install_status $status

            # Check for various failure conditions
            if test $install_status -eq 124
                echo "⏰  Installation timed out after 5 minutes"
                if not gum confirm --default=true "Continue with next version?"
                    _cleanup_on_signal
                    return 130
                end
            else if test $install_status -eq 130 -o $install_status -eq 2
                # SIGINT received during install
                _cleanup_on_signal
                return 130
            else if test $install_status -eq 0
                echo "✅  Successfully installed Node.js $ver"
            else
                echo "❌  Failed to install Node.js $ver (exit code: $install_status)"
            end
        else
            echo ""
            echo "🗑️  Uninstalling Node.js $ver... ($current_operation/$total_operations)"
            asdf uninstall nodejs $ver
            set -l uninstall_status $status

            # Check for interruption during uninstall
            if test $uninstall_status -eq 130 -o $uninstall_status -eq 2
                _cleanup_on_signal
                return 130
            else if test $uninstall_status -eq 0
                echo "✅  Successfully uninstalled Node.js $ver"
            else
                echo "❌  Failed to uninstall Node.js $ver"
            end
        end

        set current_operation (math $current_operation + 1)
    end

    echo ""
    echo "🎉 Node.js version management complete!"
    echo "📋 Final installed versions:"
    asdf list nodejs 2>/dev/null | string trim

    # Clean up trap
    trap - INT
end