function start
  if test -f ./local_env.fish
    source ./local_env.fish
  end
  if test -f ./local_start.fish
    source ./local_start.fish
  else if test -f ./package.json
    if command -v jq > /dev/null
      set scripts (jq -r '.scripts | keys[]' ./package.json)
      if contains start $scripts
        _pm_run run start -- $argv
      else if contains dev $scripts
        _pm_run run dev -- $argv
      else if contains serve $scripts
        _pm_run run serve -- $argv
      else if contains develop $scripts
        _pm_run run develop -- $argv
      else
        echo "No suitable start script found. Available scripts:"
        echo $scripts
      end
    else
      _pm_run run start -- $argv
    end
  else
    echo "No package.json or local_start.fish found"
  end
end
