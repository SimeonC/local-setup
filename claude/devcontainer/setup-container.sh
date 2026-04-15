#!/usr/bin/env bash
# Initialize devcontainer environment: copy config, install tool managers, install language deps
set -euo pipefail

echo "==> Copying host config files"
cp /tmp/host-fish-variables ~/.config/fish/fish_variables
cp /tmp/host-gitconfig ~/.gitconfig
sed -i 's|/Users/simeoncheeseman|/home/dev|g' ~/.gitconfig

echo "==> Configuring git"
git config --global commit.gpgsign false
git config --global safe.directory '*'

echo "==> Setting up SSH"
cp -r /tmp/host-ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config 2>/dev/null || true
chmod 600 ~/.ssh/id_* 2>/dev/null || true

echo "==> Fixing node_modules volume ownership"
sudo chown -R dev:dev "${CONTAINER_WORKSPACE_FOLDER:-$PWD}/node_modules" 2>/dev/null || true

echo "==> Installing tool versions via mise"
~/.local/bin/mise trust
~/.local/bin/mise install -y
fish -c authorize_npm

echo "==> Installing language dependencies"
[ -f package.json ] && { echo "    Node: npm ci"; ~/.local/bin/mise exec -- npm ci; } || true
[ -f Gemfile ] && { echo "    Ruby: bundle install"; ~/.local/bin/mise exec -- bundle install; } || true
[ -f mix.exs ] && { echo "    Elixir: mix deps.get"; ~/.local/bin/mise exec -- mix deps.get; } || true

if [ -x .devcontainer/setup.sh ]; then
    echo "==> Running project setup.sh"
    ~/.local/bin/mise exec -- .devcontainer/setup.sh
fi

if [ -f package.json ] && grep -qE '"@?playwright' package.json; then
    npx playwright install
fi

echo "==> Updating Claude Code"
claude update

echo "==> Setup complete"
