# function quality that accepts optional boolean flag `--fix`
function quality
  set -l red "\e[31m"
  set -l green "\e[32m"
  set -l yellow "\e[33m"
  set -l blue "\e[34m"
  set -l magenta "\e[35m"
  set -l cyan "\e[36m"
  set -l white "\e[37m"
  set -l reset "\e[0m"

  if test -d ./.grit
    printf "$green%s$reset\n" "Grit repository detected"
    if test "$argv[1]" = "--fix"
      printf "$cyan%s$reset\n" "[+] Running grit check --fix first"
      grit check --fix
    end
  end

  set -l ran_nx_quality 0
  if test -f ./nx.json
    set -l quality_projects (npx nx show projects --with-target=quality 2>/dev/null)
    set -l typecheck_projects (npx nx show projects --with-target=typecheck 2>/dev/null)
    set -l quality_count (count $quality_projects)
    set -l typecheck_count (count $typecheck_projects)
    if test $quality_count -gt 0; or test $typecheck_count -gt 0
      printf "$green%s$reset\n" "NX repository detected"
      if test "$argv[1]" = "--fix"
        printf "$cyan%s$reset\n" "[+] --fix detected, running format, typecheck and prettier"
        printf "$cyan%s$reset\n" "[+] npx nx affected --target=typecheck,quality --configuration=format"
        npx nx affected --target=quality --configuration=format
        smart_prettier
      else
        printf "$cyan%s$reset\n" "npx nx affected --target=quality"
        npx nx affected --target=quality
      end
      set ran_nx_quality 1
    else
      printf "$yellow%s$reset\n" "No Nx quality or typecheck targets, falling back to package.json"
    end
  end
  if test -f ./package.json; and test "$ran_nx_quality" -eq 0
    if test "$argv[1]" = "--fix"
      if string match -r "\"lint:fix\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
        printf "$cyan%s$reset\n" "npm run lint:fix"
        npm run lint:fix
      else if string match -r "\"format\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
        printf "$cyan%s$reset\n" "npm run format"
        npm run format
      else if string match -r "\"lint\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
        printf "$cyan%s$reset\n" "npm run lint -- --fix"
        npm run lint -- --fix
      end
    else
      printf "$cyan%s$reset\n" "npm run lint"
      npm run lint
    end
  else if test -f ./Gemfile
    if test "$argv[1]" = "--fix"
      if count $argv > /dev/null
        printf "$cyan%s$reset\n" "bundle exec rubocop -a $argv"
        bundle exec rubocop -a $argv
      else
        printf "$cyan%s$reset\n" "bundle exec rubocop -a"
        bundle exec rubocop -a
      end
    else
      printf "$cyan%s$reset\n" "bundle exec rubocop"
      bundle exec rubocop
    end
  else
    echo "No package.json or Gemfile found"
  end
end