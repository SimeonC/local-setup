#!/usr/bin/env bash
# Initialize devcontainer environment: copy config, install tool managers, install language deps
set -euo pipefail

# Copy host config files into container
cp /tmp/host-fish-variables ~/.config/fish/fish_variables
cp /tmp/host-gitconfig ~/.gitconfig
sed -i 's|/Users/simeoncheeseman|/home/dev|g' ~/.gitconfig

# Configure git
git config --global commit.gpgsign false
git config --global safe.directory '*'

# Set up SSH with correct permissions
cp -r /tmp/host-ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config 2>/dev/null || true
chmod 600 ~/.ssh/id_* 2>/dev/null || true

# Fix node_modules volume ownership
sudo chown -R dev:dev "${containerWorkspaceFolder}/node_modules" 2>/dev/null || true

# Install tool versions (Node, Ruby, Elixir, etc)
~/.local/bin/mise trust
~/.local/bin/mise install -y
fish -c authorize_npm

# Install language-specific dependencies
[ -f package.json ] && { echo "setup-container: installing Node deps"; npm ci; } || true
[ -f Gemfile ] && { echo "setup-container: installing Ruby deps"; bundle install; } || true
[ -f mix.exs ] && { echo "setup-container: installing Elixir deps"; mix deps.get; } || true

# Run project-specific setup (e.g., Playwright binaries)
if [ -x .devcontainer/setup.sh ]; then
    echo "setup-container: running project setup.sh"
    .devcontainer/setup.sh
fi

# Final updates
claude update
