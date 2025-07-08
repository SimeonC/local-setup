function npm_public_ci
  rm -rf node_modules
  rm -rf package-lock.json
  npm_public
  npm i
end
