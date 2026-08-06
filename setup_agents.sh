#!/bin/bash
# Generate ~/.claude/agents/*.md from checked-in templates.
#
# Usage: bash setup_agents.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/claude/agent_templates"
DEST_DIR="$HOME/.claude/agents"

CUSTOM_TEMPLATES=(
  custom-committer custom-explorer custom-planner custom-reviewer
  custom-specialist custom-worker
)
FALLBACK_AGENTS=(anthropic-explorer anthropic-worker anthropic-committer)

curated_models() {
  printf '%s\n' \
    $'claude-opus-5\tClaude Opus 5' \
    $'claude-sonnet-5\tClaude Sonnet 5' \
    $'claude-opus-4-8\tClaude Opus 4.8' \
    $'claude-haiku-4-5\tClaude Haiku 4.5' \
    $'claude-sonnet-4-6\tClaude Sonnet 4.6'
}

gateway_models() {
  [ "${CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY:-}" = "1" ] || return 1
  [ -n "${ANTHROPIC_BASE_URL:-}" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local auth_args=()
  if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    auth_args=(-H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN")
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    auth_args=(-H "x-api-key: $ANTHROPIC_API_KEY")
  else
    return 1
  fi

  # The gateway only advertises its non-first-party models (anthropic/*) when the
  # request looks like Claude Code itself, so the claude-cli User-Agent is required.
  curl -fsS --connect-timeout 5 --max-time 5 \
    "${auth_args[@]}" \
    -H "anthropic-version: 2023-06-01" \
    -A "claude-cli/2.1.222" \
    "${ANTHROPIC_BASE_URL%/}/v1/models?limit=1000" 2>/dev/null \
    | jq -r '.data[]? | select((.id | type) == "string" and (.id | test("^(claude|anthropic)")) and (.display_name? | type) == "string" and (.display_name | gsub("^[[:space:]]+|[[:space:]]+$"; "") | length > 0)) | [.id, .display_name] | @tsv' \
    | awk -F '\t' 'NF >= 2 && !seen[$1]++'
}

# Pull the single-line `description:` value from a template's frontmatter.
agent_description() {
  sed -n 's/^description:[[:space:]]*//p' "$TEMPLATE_DIR/$1.md" | head -n1
}

select_model() {
  local agent="$1" desc="$2" cols header
  cols="$(tput cols 2>/dev/null || echo 80)"
  # Wrap the description so fzf's header doesn't truncate it at terminal width.
  header="$(printf '%s' "$desc" | fold -s -w "$([ "$cols" -gt 8 ] && echo $((cols - 4)) || echo 76)")"
  printf '%s\n' "$MODELS" \
    | fzf --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
      --prompt="$agent model: " --height=16 \
      --header="$header" --header-first
}

if [ "$#" -ne 0 ]; then
  echo "error: setup_agents.sh requires interactive per-agent model selections; arguments are not supported" >&2
  exit 1
fi
if [ ! -t 0 ] || ! command -v fzf >/dev/null 2>&1; then
  echo "error: setup_agents.sh requires interactive per-agent model selections with fzf installed" >&2
  exit 1
fi

MODELS="$(gateway_models || true)"
if [ -z "$MODELS" ]; then
  MODELS="$(curated_models)"
  echo "Gateway model discovery unavailable; using curated model choices." >&2
else
  echo "Using models discovered from ${ANTHROPIC_BASE_URL%/}/v1/models." >&2
fi

CUSTOM_MODELS=()
for agent in "${CUSTOM_TEMPLATES[@]}"; do
  model="$(select_model "$agent" "$(agent_description "$agent")")"
  [ -n "$model" ] || { echo "error: no model selected for $agent" >&2; exit 1; }
  CUSTOM_MODELS+=("$model")
done
FALLBACK_MODELS=()
for agent in "${FALLBACK_AGENTS[@]}"; do
  model="$(select_model "$agent" "$(agent_description "custom-${agent#anthropic-}")")"
  [ -n "$model" ] || { echo "error: no model selected for $agent" >&2; exit 1; }
  FALLBACK_MODELS+=("$model")
done

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "error: no templates at $TEMPLATE_DIR" >&2
  exit 1
fi

if [ -L "$DEST_DIR" ]; then
  rm "$DEST_DIR"
fi
mkdir -p "$DEST_DIR"
rm -f "$DEST_DIR"/{Explore,general-purpose,Plan,explorer,worker,committer,specialist}.md

# Escape replacement text so arbitrary model IDs remain exact in sed output.
sed_replacement() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

generate_from() {
  local src="$1" name="$2" model="$3" replacement
  replacement="$(sed_replacement "$model")"
  sed -e "s|__AGENT_MODEL__|$replacement|g" \
      -e "s|__DEFAULT_HIGH_MODEL__|$replacement|g" \
      -e "s|__DEFAULT_LOW_MODEL__|$replacement|g" \
      -e "s|__DEFAULT_MODEL__|$replacement|g" \
      -e "s|^name: .*|name: $name|" \
      "$TEMPLATE_DIR/$src.md" > "$DEST_DIR/$name.md"
}

for i in "${!CUSTOM_TEMPLATES[@]}"; do
  generate_from "${CUSTOM_TEMPLATES[$i]}" "${CUSTOM_TEMPLATES[$i]}" "${CUSTOM_MODELS[$i]}"
done
for i in "${!FALLBACK_AGENTS[@]}"; do
  agent="${FALLBACK_AGENTS[$i]}"
  generate_from "custom-${agent#anthropic-}" "$agent" "${FALLBACK_MODELS[$i]}"
done
exit 0
