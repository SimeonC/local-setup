function install
  if test -f ./package.json
    if test (contains -- --clean $argv)
      _pm_run ci
    else
      _pm_run i
    end
  else if test -f ./Gemfile
    bundle install
  else
    echo "No package.json or Gemfile found"
  end
end
