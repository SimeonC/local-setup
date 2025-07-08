function test_run
  if test -f ./package.json
    npm test
  else if test -f ./Gemfile
    if count $argv > /dev/null
      bundle exec rspec $argv
    else
      bundle exec rspec
    end
  else
    echo "No package.json or Gemfile found"
  end
end
