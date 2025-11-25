function mise_default_packages --description 'Install default npm packages from config file using mise'
  set config_file "$HOME/.config/fish/configs/.default-npm-packages"

  if not test -f $config_file
    echo "Error: Config file not found at $config_file"
    return 1
  end

  set packages (cat $config_file | string replace -a '\r' '' | string trim | string match -v '^$')
  if test (count $packages) -gt 0
    npm install -g $packages
  end
end

