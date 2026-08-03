#!/bin/bash
# Generate ~/.claude/agents/*.md from the checked-in templates in
# claude/agent_templates/, substituting the default-tier model.
#
# Agent frontmatter does NOT interpolate env vars — the literal string is sent
# to the gateway and rejected. So the model must be baked in at setup time.
# That is why ~/.claude/agents is generated rather than symlinked, and why no
# gateway model ID appears in a checked-in file.
#
# Usage: sh setup_agents.sh [default-tier-model]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/claude/agent_templates"
DEST_DIR="$HOME/.claude/agents"

DEFAULT_MODEL="claude-sonnet-4-6"
# setup.sh passes the chosen model as $1. When run standalone, prompt via fzf
# instead of relying on an env var; fall back to the default non-interactively.
if [ -n "$1" ]; then
  MODEL="$1"
elif [ -t 0 ] && command -v fzf >/dev/null 2>&1; then
  MODEL="$(printf '%s\n' "$DEFAULT_MODEL" "claude-opus-5" "claude-haiku-4-5-20251001" \
    | fzf --prompt="Default model for explorer/worker agents (type to enter a gateway ID): " \
          --height=10 --print-query --query="$DEFAULT_MODEL" \
    | tail -1 || true)"
fi
: "${MODEL:=$DEFAULT_MODEL}"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "error: no templates at $TEMPLATE_DIR" >&2
  exit 1
fi

# Earlier setups symlinked this directory; a symlink cannot hold generated files.
if [ -L "$DEST_DIR" ]; then
  rm "$DEST_DIR"
fi
mkdir -p "$DEST_DIR"

for template in "$TEMPLATE_DIR"/*.md; do
  name="$(basename "$template")"
  sed "s|__DEFAULT_MODEL__|$MODEL|g" "$template" > "$DEST_DIR/$name"
done

echo "Agents generated in $DEST_DIR (default tier: $MODEL):"
for template in "$TEMPLATE_DIR"/*.md; do
  name="$(basename "$template" .md)"
  echo "  $name -> $(sed -n 's/^model: //p' "$DEST_DIR/$name.md")"
done
echo "Note: the agent registry loads at session start — restart Claude Code to pick these up."
