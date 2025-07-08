function upgrade
  printf "\033[1;34mUpgrading all package.json files...\033[0m\n"
  printf "\033[1;34mUpgrading root package.json\033[0m\n\n"
  npm-upgrade
  set -l workspaces (jq -r '.workspaces[] // empty' package.json | string trim)
  for dir in $workspaces
    set -l convertedDir (string replace '/*' '' $dir)
    set -l convertedDir "./$convertedDir"
    set -l convertedDir (string replace '//' '/' $convertedDir)
    for package in (find $convertedDir -name 'package.json' -not -path '*node_modules*' -not -path '*dist*' -print0 | xargs -0 -n1 dirname)
      pushd $package
      set -l package (string replace './' '' $package)
      printf "\n\033[1;34mUpgrading $package\033[0m\n\n"
      npm-upgrade
      popd
    end
  end
end

