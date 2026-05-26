function test_watch
  if test -f ./package.json
    if string match -r "\"test:watch\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      _pm_run run test:watch
    else if string match -r "\"watch:test\":\\s*\"[^\"\\n]+" -q -- (cat ./package.json)
      _pm_run run watch:test
    else if string match -r "\"test\":\\s*\"vitest[^\"\\n]*" -q -- (cat ./package.json)
      _pm_run run test
    else if string match -r "\"test\":\\s*\"[^\"\\n]*" -q -- (cat ./package.json)
      _pm_run run test -- --watch
    else
      echo "No `test:watch` or `watch:test` script found in package.json"
    end
  else if test -f ./Gemfile
    if count $argv > /dev/null
      _pm_exec nodemon --watch . --ext rb --exec "bundle exec rspec $argv || true"
    else
      _pm_exec nodemon --watch . --ext rb --exec "bundle exec rspec || true"
    end
  else
    echo "No package.json or Gemfile found"
  end
end
