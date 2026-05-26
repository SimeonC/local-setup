function dev
  if test -f ./local_env.fish
    source ./local_env.fish
  end
  if test -f ./local_dev.fish
    source ./local_dev.fish
  else if test -f ./package.json
    if string match -r "\"dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      _pm_run run dev -- $argv
    else if string match -r "\"test:dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      _pm_run run test:dev -- $argv
    else if string match -r "\"start:local-monolith\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      _pm_run run start:local-monolith -- $argv
    else
      echo "No `dev` or `test:dev` script found in package.json, trying `start`"
      start
    end
  else
    start
  end
end
