#!/bin/bash
# Setup symlinks for dotfiles managed in this repo

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Claude Code: CLAUDE.md
ln -sfn "$SCRIPT_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md

# Claude Code: skills
ln -sfn "$SCRIPT_DIR/claude/skills" ~/.claude/skills

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
for hook in "$SCRIPT_DIR"/claude/hooks/*; do
  echo "  ~/.claude/hooks/$(basename "$hook") -> $hook"
done
echo "  ~/.grit/patterns -> $SCRIPT_DIR/grit_patterns"
