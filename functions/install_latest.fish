function install_latest_in
  set -l dir $argv[1]
  set -l globs $argv[2..-1]
  set -l package_json "$dir/package.json"
  set -l package_json_tmp "$dir/package.json.tmp"
  if not test -f $package_json
    return
  end
  cp $package_json $package_json_tmp
  printf "\033[1;34mUpgrading $package_json...\033[0m\n"
  set -l dependency_keys (jq -r 'keys[]' $package_json_tmp | grep -i 'dependencies')
  for key in $dependency_keys
    printf "\033[34m  [$key]\033[0m\n"
    set -l packages
    for glob in $globs
      set -l regex (string replace -r '\\*' '.*' $glob)
      set -l glob_packages (jq -r ".$key | to_entries[] | select(.key | test(\"$regex\")) | .key" $package_json_tmp)
      set packages $packages $glob_packages
    end
    if test (count (string split " " $packages)) -eq 0
      printf "    No packages found.\n"
      continue
    end
    for package in (string split " " $packages)
      printf "   - $package: "
      set -l raw_version (jq -r ".\"$key\"[\"$package\"]" $package_json_tmp)
      set -l current_version (string replace -r '\^' '' $raw_version)
      if test $current_version = "*"
        printf "\033[36m*\033[0m\n"
        continue
      end
      set -l latest_version (npm show $package version)
      set -l latest_version_parts (string lower (string split "." $latest_version))
      set -l current_version_parts (string lower (string split "." $current_version))
      if string match -q "^*" "$raw_version" = "$raw_version"
        set latest_version "^$latest_version_parts[1]"
        set -l new_latest_version_parts ()
        set -a new_latest_version_parts $latest_version_parts[1]
        for i in (seq 2 (count $latest_version_parts))
          if test -z $current_version_parts[$i]
            set -a new_latest_version_parts "x"
          else if "$current_version_parts[$i]" = "x"
            set -a new_latest_version_parts "x"
          else
            set -a new_latest_version_parts $latest_version_parts[$i]
            set latest_version "$latest_version.$latest_version_parts[$i]"
          end
        end
        set latest_version_parts $new_latest_version_parts
      end

      if test $latest_version = $current_version -o $latest_version = $raw_version
        printf "\033[36m[latest]\033[0m\n"
        continue
      end

      set -l latest_major $latest_version_parts[1]
      set -l latest_minor $latest_version_parts[2]
      set -l latest_patch_with_pre $latest_version_parts[3]
      set -l latest_patch (string split "-" $latest_patch_with_pre)[1]

      set -l current_major $current_version_parts[1]
      set -l current_minor $current_version_parts[2]
      set -l current_patch_with_pre $current_version_parts[3]
      set -l current_patch (string split "-" $current_patch_with_pre)[1]
      set -l current_prerelease (string split "-" $current_patch_with_pre)[2]

      printf "$current_version -> "
      if test $latest_major -gt $current_major
        printf "\033[1;31m$latest_major.$latest_minor.$latest_patch\033[0m\n"
      else if test $latest_minor = "x" -o $latest_minor -gt $current_minor
        printf "\033[33m$latest_major.\033[1;33m$latest_minor.$latest_patch\033[0m\n"
      else if test $latest_patch = "x" -o $latest_patch -gt $current_patch
        printf "\033[32m$latest_major.$latest_minor.\033[1;32m$latest_patch\033[0m\n"
      else if test -n $current_prerelease
        printf "\033[35m$latest_major.$latest_minor.$latest_patch\033[0m\n"
      else
        printf "\033[34m$latest_version\033[0m\n"
      end
      jq ".\"$key\"[\"$package\"] = \"$latest_version\"" $package_json_tmp > $package_json_tmp.tmp
      mv $package_json_tmp.tmp $package_json_tmp
    end
  end
  mv $package_json_tmp $package_json
  npx prettier --log-level=error --write $package_json
end

function install_latest
  if test ! -f package.json
    printf "\033[1;31mNo package.json found.\033[0m\n"
    return
  end
  install_latest_in . $argv
  if test (jq '.workspaces? | length' package.json) -eq 0
    printf "\033[1;34mNo workspaces found.\033[0m\n"
    return
  end
  set -l workspaces (jq -r '.workspaces[] // empty' package.json | string trim)
  for dir_glob in $workspaces
    for dir in (string split " " (eval echo $dir_glob))
      set dir (string replace -r '^\.\/' '' $dir)
      install_latest_in "./$dir" $argv
    end
  end
end

