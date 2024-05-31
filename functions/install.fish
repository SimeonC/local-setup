function install
  if test -f ./package.json
    npm i
  else if test -f ./Gemfile
    bundle install
  else
    echo "No package.json or Gemfile found"
  end
end
