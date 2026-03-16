#!/usr/bin/env bash
# Detect ports from project config and forward them to host.docker.internal via socat.
# Usage: forward-ports.sh <project-dir>
set -uo pipefail

PROJECT_DIR="${1:-.}"
PID_FILE="/tmp/socat-forward.pids"
PORTS=()

# Kill existing forwarders
if [[ -f "$PID_FILE" ]]; then
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < "$PID_FILE"
  rm -f "$PID_FILE"
fi

read_ports_file() {
  local file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line// /}"
    [[ -n "$line" ]] && PORTS+=("$line")
  done < "$file"
}

# 0. .devcontainer/ports.local — personal/gitignored overrides
if [[ -f "$PROJECT_DIR/.devcontainer/ports.local" ]]; then
  read_ports_file "$PROJECT_DIR/.devcontainer/ports.local"
fi

# 1. .devcontainer/ports — explicit, committed port list
if [[ -f "$PROJECT_DIR/.devcontainer/ports" ]]; then
  read_ports_file "$PROJECT_DIR/.devcontainer/ports"
fi

# 2. vite.config.* — port: <number>
while IFS= read -r file; do
  while IFS= read -r port; do
    PORTS+=("$port")
  done < <(grep -oP 'port\s*:\s*\K\d+' "$file" 2>/dev/null || true)
done < <(find "$PROJECT_DIR" -name 'vite.config.*' -not -path '*/node_modules/*' 2>/dev/null || true)

# 3. .env files — PORT/VITE_PORT/DEV_PORT/APP_PORT=<number>
while IFS= read -r file; do
  while IFS= read -r port; do
    PORTS+=("$port")
  done < <(grep -oP '^(PORT|VITE_PORT|DEV_PORT|APP_PORT)=\K\d+' "$file" 2>/dev/null || true)
done < <(find "$PROJECT_DIR" \( -name '.env' -o -name '.env.local' -o -name '.env.development' \) -not -path '*/node_modules/*' 2>/dev/null || true)

# 4. package.json — --port <number> or -p <number> in scripts
while IFS= read -r file; do
  while IFS= read -r port; do
    PORTS+=("$port")
  done < <(grep -oP '(--port[= ]|-p )\K\d+' "$file" 2>/dev/null || true)
done < <(find "$PROJECT_DIR" -name 'package.json' -not -path '*/node_modules/*' 2>/dev/null || true)

# Deduplicate
if [[ ${#PORTS[@]} -gt 0 ]]; then
  mapfile -t PORTS < <(printf '%s\n' "${PORTS[@]}" | sort -un)
fi

if [[ ${#PORTS[@]} -eq 0 ]]; then
  echo "forward-ports: no ports detected" >&2
  exit 0
fi

for port in "${PORTS[@]}"; do
  if (: > /dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
    echo "forward-ports: skipping $port (already listening)" >&2
    continue
  fi
  setsid nohup socat TCP-LISTEN:"$port",fork,reuseaddr TCP:host.docker.internal:"$port" > /tmp/socat-"$port".log 2>&1 &
  echo $! >> "$PID_FILE"
  echo "forward-ports: $port -> host.docker.internal:$port"
done
