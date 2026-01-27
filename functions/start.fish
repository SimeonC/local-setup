function start
  if test -f ./package.json
    if command -v jq > /dev/null
      set scripts (jq -r '.scripts | keys[]' ./package.json)
      if contains start $scripts
        echo "npm start -- $argv"
        npm start -- $argv
      else if contains dev $scripts
        echo "npm run dev -- $argv"
        npm run dev -- $argv
      else if contains serve $scripts
        echo "npm run serve -- $argv"
        npm run serve -- $argv
      else if contains develop $scripts
        echo "npm run develop -- $argv"
        npm run develop -- $argv
      else
        echo "No suitable start script found. Available scripts:"
        echo $scripts
      end
    else
      npm start -- $argv
    end
  else if test -f ./local_start.fish
    source ./local_start.fish
  else
    echo "No package.json or local_start.fish found"
  end
end
