function typecheck
  set -l red "\e[31m"
  set -l green "\e[32m"
  set -l yellow "\e[33m"
  set -l blue "\e[34m"
  set -l magenta "\e[35m"
  set -l cyan "\e[36m"
  set -l white "\e[37m"
  set -l reset "\e[0m"

  if test -f ./nx.json
    printf "$green%s$reset\n" "NX repository detected"
    printf "$cyan%s$reset\n" "Running nx affected --target=typecheck"
    _pm_exec nx affected --target=typecheck
  else if test -f ./package.json
    if string match -r "\"typecheck\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      printf "$cyan%s$reset\n" "Running typecheck"
      _pm_run run typecheck
    else if string match -r "\"tsc\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      printf "$cyan%s$reset\n" "Running tsc"
      _pm_run run tsc
    else if test -f ./tsconfig.json
      printf "$cyan%s$reset\n" "Running tsc --noEmit"
      _pm_exec tsc --noEmit
    else
      echo "No typecheck, tsc script, or tsconfig.json found"
    end
  else
    echo "No package.json or Gemfile found"
  end
end
