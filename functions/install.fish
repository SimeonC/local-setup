function install
  if test -f ./package.json
    if test (contains -- --clean $argv)
      npm ci
    else
      npm i
    end
  else if test -f ./Gemfile
    bundle install
  else
    echo "No package.json or Gemfile found"
  end
end
