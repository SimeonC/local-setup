function dev
  if test -f ./package.json
    if string match -r "\"dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run dev"
      npm run dev
    else if string match -r "\"test:dev\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run test:dev"
      npm run test:dev
    else if string match -r "\"start:local-monolith\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      echo "npm run start:local-monolith"
      npm run start:local-monolith
    else
      echo "No `dev` or `test:dev` script found in package.json, trying `start`"
      start
    end
  else if test -f ./Gemfile
    echo "env FORCE_EMBEDDED_SETTINGS=true bundle exec rails s"
    env FORCE_EMBEDDED_SETTINGS=true bundle exec rails s
  else
    echo "No package.json or Gemfile found"
  end
end
