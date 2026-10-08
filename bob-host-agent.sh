#!/usr/bin/env bash
################################################################################
# bob-host-agent.sh
#
# Host-side agent that the bob-bridge Docker container calls via a Unix socket
# to generate rover trick scripts. Runs directly on the Ubuntu machine so it
# can switch WiFi (which Docker containers cannot do).
#
# Flow when triggered by the browser "Generate with Bob" panel:
#   1. Switch WiFi from rover network → internet network
#   2. Run Bob Shell to generate the script JSON
#   3. docker compose build client  (bundles the new script into the image)
#   4. Switch WiFi back to rover network
#   5. docker compose up -d client  (bring the client back up)
#   6. Return the generated script JSON over the socket
#
# The socket file path must match the volume mount in docker-compose.yml:
#   /tmp/bob-host-agent.sock
#
# Usage:
#   chmod +x bob-host-agent.sh
#   ./bob-host-agent.sh          # runs in foreground; use & or a systemd unit
#
# Prerequisites:
#   - Bob Shell installed and BOB_API_KEY set (via services/.env)
#   - docker / docker compose v2
#   - NetworkManager (nmcli) with both WiFi profiles already saved
#   - socat  (sudo apt install -y socat)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/services/.env"
SOCKET_PATH="/tmp/bob-host-agent.sock"
COMPOSE_FILE="$SCRIPT_DIR/services/docker-compose.yml"
WORKSPACE="$SCRIPT_DIR"

# ─── Load .env ────────────────────────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${BOB_API_KEY:?BOB_API_KEY is not set. Add it to services/.env}"
: "${INTERNET_WIFI:?INTERNET_WIFI is not set. Add it to services/.env}"

# Rover WiFi is always OL_DEMO — override via .env only if needed
ROVER_WIFI="${ROVER_WIFI:-OL_DEMO}"

export BOB_API_KEY

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[bob-host-agent] $*" >&2; }

detect_wifi_iface() {
  nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}'
}

switch_wifi() {
  local profile="$1"
  local iface
  iface="$(detect_wifi_iface)"
  log "Switching WiFi to: $profile"
  nmcli device wifi connect "$profile" ifname "$iface" 2>/dev/null \
    || nmcli connection up "$profile" ifname "$iface"
  sleep 3
}

# ─── Request handler ──────────────────────────────────────────────────────────
# Called once per connection. Reads a JSON line from stdin:
#   {"prompt": "do a figure 8"}
# Writes a JSON response to stdout:
#   {"ok": true,  "script": { ...CommandScript... }}
#   {"ok": false, "error": "reason"}
handle_request() {
  local raw_request
  read -r raw_request

  # Parse prompt from JSON using only bash + sed (no jq dependency)
  local prompt
  prompt="$(echo "$raw_request" | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')"

  if [ -z "$prompt" ]; then
    echo '{"ok":false,"error":"Missing or empty prompt field"}'
    return
  fi

  log "Received prompt: $prompt"

  # ── 1. Switch to internet WiFi ──────────────────────────────────────────────
  switch_wifi "$INTERNET_WIFI" || {
    echo '{"ok":false,"error":"Failed to switch to internet WiFi"}'
    return
  }

  # ── 2. Run Bob Shell ────────────────────────────────────────────────────────
  log "Calling Bob Shell..."
  local bob_output
  bob_output="$(cd "$WORKSPACE" && bob -p \
    "You are operating under the rover-spec skill. Follow the rover-spec skill instructions exactly. Generate a rover trick script for this description: $prompt" \
    2>&1)" || {
    switch_wifi "$ROVER_WIFI" || true
    local escaped
    escaped="$(echo "$bob_output" | sed 's/"/\\"/g' | tr -d '\n')"
    echo "{\"ok\":false,\"error\":\"Bob Shell failed: $escaped\"}"
    return
  }
  log "Bob Shell finished."

  # ── 3. Find the script Bob wrote ────────────────────────────────────────────
  local scripts_dir="$WORKSPACE/specs/scripts"
  # Detect by looking for the newest JSON file written in the last 60 seconds
  local new_script
  new_script="$(find "$scripts_dir" -name "*.json" -newer "$WORKSPACE/specs/free-roam-spec.md" \
    -not -name "README*" 2>/dev/null | sort -t/ -k1 | tail -1)"

  if [ -z "$new_script" ]; then
    switch_wifi "$ROVER_WIFI" || true
    echo '{"ok":false,"error":"Bob finished but no new script file was found"}'
    return
  fi
  log "Script written: $new_script"

  # ── 4. Rebuild client container ─────────────────────────────────────────────
  log "Rebuilding client container..."
  docker compose -f "$COMPOSE_FILE" build client 2>&1 | \
    while IFS= read -r line; do log "  docker: $line"; done

  # ── 5. Switch back to rover WiFi ────────────────────────────────────────────
  switch_wifi "$ROVER_WIFI" || {
    echo '{"ok":false,"error":"Script generated and client built but failed to switch back to rover WiFi"}'
    return
  }

  # ── 6. Restart client container ─────────────────────────────────────────────
  log "Restarting client container..."
  docker compose -f "$COMPOSE_FILE" up -d client 2>&1 | \
    while IFS= read -r line; do log "  docker: $line"; done

  # ── 7. Return the script JSON ────────────────────────────────────────────────
  local script_json
  script_json="$(cat "$new_script")"
  # Wrap in response envelope
  printf '{"ok":true,"script":%s}\n' "$script_json"
  log "Done. Returned script: $(echo "$script_json" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
}

# ─── Socket server ────────────────────────────────────────────────────────────
# Remove stale socket if present
rm -f "$SOCKET_PATH"

log "Listening on $SOCKET_PATH"
log "INTERNET_WIFI=$INTERNET_WIFI  ROVER_WIFI=$ROVER_WIFI"
log "Press Ctrl+C to stop."

# socat forks a subprocess for each connection; handle_request runs in that fork
export -f handle_request switch_wifi detect_wifi_iface log
export COMPOSE_FILE WORKSPACE INTERNET_WIFI ROVER_WIFI BOB_API_KEY

socat UNIX-LISTEN:"$SOCKET_PATH",fork,mode=660 \
  EXEC:"bash -c handle_request",nofork
