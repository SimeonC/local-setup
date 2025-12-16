function start
  if test -f ./package.json
    if command -v jq > /dev/null
      set scripts (jq -r '.scripts | keys[]' ./package.json)
      if contains start $scripts
        echo "npm start"
        npm start
      else if contains dev $scripts
        echo "npm run dev"
        npm run dev
      else if contains serve $scripts
        echo "npm run serve"
        npm run serve
      else if contains develop $scripts
        echo "npm run develop"
        npm run develop
      else
        echo "No suitable start script found. Available scripts:"
        echo $scripts
      end
    else
      npm start
    end
  else if test -f ./Gemfile
    echo "Starting MongoDB"
    docker start ts_mongodb
    echo "bundle exec rails s"
    bundle exec rails s
  else
    echo "No package.json or Gemfile found"
  end
end
