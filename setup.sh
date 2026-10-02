#!/bin/bash
# Setup symlinks for dotfiles managed in this repo

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ask_yes_no PROMPT — interactive fzf Yes/No picker. Returns 0 for Yes.
# Defaults to No when non-interactive or fzf is missing.
ask_yes_no() {
  if [ -t 0 ] && command -v fzf >/dev/null 2>&1; then
    [ "$(printf 'No\nYes\n' | fzf --prompt="$1 " --height=6 || true)" = "Yes" ]
  else
    return 1
  fi
}

# Install Homebrew itself if missing (the official bootstrap installer).
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Put brew on PATH for the rest of this script (Apple Silicon then Intel).
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_bin" ] && eval "$("$brew_bin" shellenv)"
  done
fi

# Install base dependencies (idempotent). Guarded so the script still runs the
# symlink work if Homebrew install failed, and a single failed package or
# `set -e` does not abort the rest of setup.
if command -v brew >/dev/null 2>&1; then
  echo "Installing base dependencies via brew..."
  # `gh` (autoplan PR phase, prclaude) and `fzf` (model/branch/root pickers) are
  # required. colima/docker provide the container runtime.
  for pkg in git jq fish mise gum mdcat glow yq dotenvx/brew/dotenvx gh fzf colima docker uv go; do
    brew install "$pkg" || echo "  ⚠️  brew install $pkg failed — continuing"
  done
  # gh extension install is NOT idempotent (errors if already present) — guard it.
  if command -v gh >/dev/null 2>&1; then
    if gh extension list 2>/dev/null | grep -q 'github/gh-stack'; then
      echo "  gh-stack extension already installed"
    elif ask_yes_no "Install github/gh-stack gh extension (autoplan stack_base)?"; then
      gh extension install github/gh-stack || echo "  ⚠️  gh extension install github/gh-stack failed — continuing"
    else
      echo "  Skipping gh-stack extension"
    fi
  fi
  uv tool install graphifyy
else
  echo "⚠️  Homebrew unavailable — skipping dependency install. Install deps manually (see README)."
fi

# Create ~/.claude and ~/.agents if they don't exist
mkdir -p ~/.claude ~/.agents

# ~/.agents/skills: use the same skill source as Claude Code. Preserve a
# pre-existing real directory rather than deleting it when converting to the symlink.
if [ -e ~/.agents/skills ] && [ ! -L ~/.agents/skills ]; then
  mv ~/.agents/skills ~/.agents/skills.backup
fi
ln -sfn "$SCRIPT_DIR/claude/skills" ~/.agents/skills

# Claude Code: CLAUDE.md
ln -sfn "$SCRIPT_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md

# Claude Code: skills
ln -sfn "$SCRIPT_DIR/claude/skills" ~/.claude/skills

# Claude Code: workflows (saved Workflow scripts, invoked by scriptPath/name)
ln -sfn "$SCRIPT_DIR/claude/workflows" ~/.claude/workflows

# Claude Code: agents — GENERATED, not symlinked. Agent frontmatter does not
# interpolate env vars, so each agent's selected model is baked in at setup time.
# This keeps gateway model IDs out of checked-in files.
bash "$SCRIPT_DIR/setup_agents.sh"

# Claude Code: hooks (symlink individual files, NOT the folder — ~/.claude/hooks
# also holds machine-local hooks like monitor.sh/statusline.sh that are not in this repo)
mkdir -p ~/.claude/hooks
for hook in "$SCRIPT_DIR"/claude/hooks/*; do
  ln -sfn "$hook" ~/.claude/hooks/"$(basename "$hook")"
done

# Claude Code: peer-programming plugin dev-mod symlink.
# The canonical source is in this repo at claude-plugins/peer-programming.
# Create or refresh a symlink in ~/.claude/dev-mods pointing to it for hot-reload.
# Leave a pre-existing real directory untouched with a warning.
PEER_PLUGIN_SRC="$SCRIPT_DIR/claude-plugins/peer-programming"
PEER_PLUGIN_LINK="$HOME/.claude/dev-mods/4edef55f-ceee-4925-8001-a069491fb871/peer-programming"
if [ -d "$PEER_PLUGIN_SRC" ]; then
  mkdir -p "$(dirname "$PEER_PLUGIN_LINK")"
  if [ -L "$PEER_PLUGIN_LINK" ] || [ ! -e "$PEER_PLUGIN_LINK" ]; then
    ln -sfn "$PEER_PLUGIN_SRC" "$PEER_PLUGIN_LINK"
  else
    echo "  ⚠️  $PEER_PLUGIN_LINK exists and is not a symlink — leaving it untouched"
  fi
else
  echo "  ⚠️  Peer plugin source is missing at $PEER_PLUGIN_SRC — skipping dev-mod symlink"
fi

# If this repository is not already ~/.config/fish, expose the entire local
# marketplace there without replacing a pre-existing real directory.
FISH_PLUGIN_CATALOG="$HOME/.config/fish/claude-plugins"
if [ "$SCRIPT_DIR/claude-plugins" != "$FISH_PLUGIN_CATALOG" ]; then
  if [ -L "$FISH_PLUGIN_CATALOG" ] || [ ! -e "$FISH_PLUGIN_CATALOG" ]; then
    ln -sfn "$SCRIPT_DIR/claude-plugins" "$FISH_PLUGIN_CATALOG"
  else
    echo "  ⚠️  $FISH_PLUGIN_CATALOG exists and is not a symlink — leaving it untouched"
  fi
fi

# Grit patterns
mkdir -p ~/.grit
ln -sfn "$SCRIPT_DIR/grit_patterns" ~/.grit/patterns

# Alfred "Launch" workflow: build the Go binary and link the workflow into
# Alfred. Alfred runs a Script Filter with the workflow folder as its working
# directory, so the filter calls the binary as ./alfred and it must sit next to
# info.plist. The link keeps the workflow's UUID directory name so Alfred keeps
# the workflow's identity and bindings.
# Alfred can sync its preferences to a custom folder (Alfred → Advanced →
# Syncing), so read that location rather than assuming the default.
ALFRED_SYNC="$(defaults read com.runningwithcrayons.Alfred-Preferences syncfolder 2>/dev/null || true)"
ALFRED_SYNC="${ALFRED_SYNC/#\~/$HOME}"
[ -d "$ALFRED_SYNC/Alfred.alfredpreferences/workflows" ] || ALFRED_SYNC="$HOME/Library/Application Support/Alfred"

ALFRED_DIR="$SCRIPT_DIR/alfred-launch"
ALFRED_WORKFLOW="$ALFRED_DIR/workflow"
ALFRED_WORKFLOW_LINK="$ALFRED_SYNC/Alfred.alfredpreferences/workflows/user.workflow.1C804719-BF45-4D7A-B15F-4C7C1C0880C3"
if [ -d "$ALFRED_WORKFLOW" ]; then
  if command -v go >/dev/null 2>&1; then
    if (cd "$ALFRED_DIR" && go build -o workflow/alfred .); then
      echo "  Built $ALFRED_WORKFLOW/alfred"
    else
      echo "  ⚠️  go build failed — the Launch workflow will not run until this is fixed"
    fi
  else
    echo "  ⚠️  go not found — skipping alfred workflow build"
  fi

  if [ -d "$(dirname "$ALFRED_WORKFLOW_LINK")" ]; then
    ln -sfn "$ALFRED_WORKFLOW" "$ALFRED_WORKFLOW_LINK"
  else
    echo "  ⚠️  Alfred workflows directory not found — skipping workflow link"
  fi
else
  echo "  ⚠️  $ALFRED_WORKFLOW is missing — skipping Alfred workflow setup"
fi

echo "Show hidden dot files by default..."
defaults write com.apple.finder AppleShowAllFiles -boolean true; killall Finder;

echo "Symlinks created:"
echo "  ~/.agents/skills -> $SCRIPT_DIR/claude/skills"
echo "  ~/.claude/CLAUDE.md -> $SCRIPT_DIR/claude/CLAUDE.md"
echo "  ~/.claude/skills -> $SCRIPT_DIR/claude/skills"
echo "  ~/.claude/workflows -> $SCRIPT_DIR/claude/workflows"
echo "  ~/.claude/agents  (generated from claude/agent_templates, models selected interactively)"
for hook in "$SCRIPT_DIR"/claude/hooks/*; do
  echo "  ~/.claude/hooks/$(basename "$hook") -> $hook"
done
echo "  ~/.grit/patterns -> $SCRIPT_DIR/grit_patterns"
echo "  Alfred Launch workflow -> $SCRIPT_DIR/alfred-launch/workflow (built: workflow/alfred)"
