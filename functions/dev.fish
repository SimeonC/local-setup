function dev
  if test -f ./package.json
    if string match -r "\"dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run dev -- $argv"
      npm run dev -- $argv
    else if string match -r "\"test:dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run test:dev -- $argv"
      npm run test:dev -- $argv
    else if string match -r "\"start:local-monolith\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run start:local-monolith -- $argv"
      npm run start:local-monolith -- $argv
    else
      echo "No `dev` or `test:dev` script found in package.json, trying `start`"
      start
    end
  else if test -f ./local_dev.fish
    source ./local_dev.fish
  else
    start
  end
end
