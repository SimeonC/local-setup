#!/bin/sh
# statusline.sh — Claude Code statusLine hook
# Reads statusLine JSON from stdin and outputs statusbar text.
# Sibling scripts (statusline-*.sh) are sourced for side-effects.

input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
for ext in "$HOOK_DIR"/statusline-*.sh; do
    [ -f "$ext" ] && . "$ext"
done

if [ -n "$used" ] && [ -n "$remaining" ]; then
    used=$(printf '%.0f' "$used")
    remaining=$(printf '%.0f' "$remaining")
    if [ "$used" -lt 50 ]; then
        alert_fore="\033[36m"
    elif [ "$used" -lt 70 ]; then
        alert_fore="\033[33m"
    else
        alert_fore="\033[31m"
    fi
    # Glyphs built via printf; a source literal gets corrupted during loop concatenation.
    full=$(printf '\342\226\210')   # █ U+2588 full block
    light=$(printf '\xE2\x96\x92')  # ▒ U+2591 medium shade
    rrail=$(printf '\xE2\x96\x8F')  # ▏ U+258F left one-eighth block
    lrail=$(printf '\xE2\x96\x95')  # ▕ U+2595 left one-eighth block
    used_blocks=""
    remaining_blocks=""
    steps=10
    case "$model" in
        *"1M context"*|*"[1M]"*) steps=20 ;;
    esac
    for i in $(seq 1 $steps); do
        if [ $((i * (100 / $steps))) -le "$used" ]; then
            used_blocks="$used_blocks$full"
        else
            remaining_blocks="$remaining_blocks$light"
        fi
    done
    printf "%s  $alert_fore%s%s%s%s %.0f%%\033[0m\n" "$model" "$lrail" "$used_blocks" "$remaining_blocks" "$rrail" "$used"
else
    printf "%s" "$model"
fi
