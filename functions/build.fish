function build
  if test -f ./package.json
    _pm_run run build
  else
    echo "No package.json found"
  end
end
