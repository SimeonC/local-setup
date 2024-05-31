function build
  if test -f ./package.json
    echo "npm run build"
    npm run build
  else
    echo "No package.json found"
  end
end
