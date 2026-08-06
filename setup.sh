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
  for pkg in git jq fish mise gum mdcat glow yq dotenvx/brew/dotenvx gh fzf colima docker uv; do
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

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Claude Code: CLAUDE.md
ln -sfn "$SCRIPT_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md

# Claude Code: skills
ln -sfn "$SCRIPT_DIR/claude/skills" ~/.claude/skills

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

# Grit patterns
mkdir -p ~/.grit
ln -sfn "$SCRIPT_DIR/grit_patterns" ~/.grit/patterns

echo "Symlinks created:"
echo "  ~/.claude/CLAUDE.md -> $SCRIPT_DIR/claude/CLAUDE.md"
echo "  ~/.claude/skills -> $SCRIPT_DIR/claude/skills"
echo "  ~/.claude/agents  (generated from claude/agent_templates, models selected interactively)"
for hook in "$SCRIPT_DIR"/claude/hooks/*; do
  echo "  ~/.claude/hooks/$(basename "$hook") -> $hook"
done
echo "  ~/.grit/patterns -> $SCRIPT_DIR/grit_patterns"
