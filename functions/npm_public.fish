function npm_public
  rm ~/.npmrc
  npm config set registry=https://registry.npmjs.org/
  npm config set save-exact=true
end

