function lerna
  if test -f node_modules/.bin/lerna
    node_modules/.bin/lerna $argv
  else
    echo "No local lerna installation detected..."
  end
end
