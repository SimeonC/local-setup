# Setup Instructions

### Install basic packages

`./setup.sh` (see below) installs Homebrew if missing, then installs all base packages. Homebrew and these packages are listed here for reference / manual install:

```sh
# Homebrew (setup.sh runs this automatically when brew is missing)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install git
brew install jq
brew install fish
brew install mise
brew install gum
brew install mdcat
brew install glow
brew install dotenvx/brew/dotenvx # required by autoplan's env_files frontmatter
brew install yq # required by autoplan's frontmatter parsing
brew install gh # required by autoplan's PR phase and prclaude
brew install fzf # required by setup.sh's pickers and autoplan's branch/root pickers
brew install colima docker # container runtime
gh extension install github/gh-stack # required by autoplan's stack_base frontmatter (setup.sh prompts to install)
```

`setup.sh` prompts (via fzf) for the default agent model and whether to install the gh-stack extension — no env vars required.

### Start Colima (Docker)

```sh
colima start --cpu 4 --memory 8 --disk 100 --vm-type vz --mount-type sshfs --ssh-agent --activate --save-config
```

This saves the configuration to `~/.colima/_templates/default.yaml` so future `colima start` uses the same settings.

### Install Applications

- Arc
- 1password
- VSCode
- TowerGit
- Alfred
- Kaleidoscope
- Talon
- iStat Menus
- Sip
- CleanShot
- PixelSnap
- Yaak
- Discord
- Docker
- Figma
- Forklift
- Patterns
- Silicio
- Slack

### Setup Tower

Enable GPG keys and use the anonymous github profile.

### Setup Alfred

Use locally stored alfedpreferences file

### Checkout this package

This package should be checked out to `~/.config/fish` directory

### Install fish extensions

Go here, pick your favourites https://github.com/jorgebucaran/awsm.fish

### Setup mise

Generate fish completions and add idiomatic file support. (See https://mise.jdx.dev/installing-mise.html for more setup notes)

```sh
mise completion fish > ~/.config/fish/completions/mise.fish
mise settings add idiomatic_version_file_enable_tools ruby
mise settings add idiomatic_version_file_enable_tools node
```

### Setup Talon

After installing Talon main, checkout these repositories and configure;

- https://github.com/SimeonC/knausj_talon
- https://github.com/cursorless-dev/cursorless
- https://github.com/chaosparrot/talon_hud

### Run setup script

Creates symlinks for Claude Code config (`CLAUDE.md`, `skills/`, `hooks/*`) and grit patterns.

```sh
./setup.sh
```

### Loading web-extensions

To load/update web extensions it TamperMonkey/OrangeMonkey or similar.

1. `cd ./web-extensions`
2. `npm run start`
3. Inside extension settings use "Import from URL"
4. Enter in `http://127.0.0.1:9876/<script name>`
