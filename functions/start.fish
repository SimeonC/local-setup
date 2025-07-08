function start
  if test -f ./package.json
    echo "npm start"
    npm start
  else if test -f ./Gemfile
    echo "bundle exec rails s"
    bundle exec rails s
  else
    echo "No package.json or Gemfile found"
  end
end
