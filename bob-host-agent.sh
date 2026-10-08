#!/usr/bin/env bash
################################################################################
# bob-host-agent.sh
#
# Host-side agent that the bob-bridge Docker container calls via a Unix socket
# to generate rover trick scripts. Runs directly on the Ubuntu machine so it
# can call Bob Shell and rebuild Docker containers.
#
# The laptop connects to the rover via OL_DEMO WiFi and has internet via
# ethernet simultaneously — no WiFi switching needed.
#
# Flow when triggered by the browser "Generate with Bob" panel:
#   1. Run Bob Shell to generate the script JSON  (internet via ethernet)
#   2. docker-compose build client                (bundles new script)
#   3. docker-compose up -d client                (brings client back up)
#   4. Return the generated script JSON over the socket → browser
#
# The socket file path must match the volume mount in docker-compose.yml:
#   /tmp/bob-host-agent.sock
#
# Usage:
#   chmod +x bob-host-agent.sh
#   ./bob-host-agent.sh    # keep running in a terminal alongside docker-compose
#
# Prerequisites:
#   - Bob Shell installed and working  (bob -p "hello" works)
#   - BOB_API_KEY set in services/.env
#   - docker-compose v2
#   - socat  (already installed)
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
export BOB_API_KEY

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[bob-host-agent] $*" >&2; }

# ─── Request handler ──────────────────────────────────────────────────────────
# Reads one JSON line from stdin: {"prompt": "do a figure 8"}
# Writes one JSON line to stdout:
#   {"ok": true,  "script": { ...CommandScript... }}
#   {"ok": false, "error": "reason"}
handle_request() {
  local raw_request
  read -r raw_request

  # Extract prompt from JSON using sed (no jq needed)
  local prompt
  prompt="$(echo "$raw_request" | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')"

  if [ -z "$prompt" ]; then
    echo '{"ok":false,"error":"Missing or empty prompt field"}'
    return
  fi

  log "Received prompt: $prompt"

  # ── 1. Run Bob Shell ────────────────────────────────────────────────────────
  log "Calling Bob Shell..."
  local bob_output
  bob_output="$(cd "$WORKSPACE" && bob -p \
    "You are operating under the rover-spec skill. Follow the rover-spec skill instructions exactly. Generate a rover trick script for this description: $prompt" \
    2>&1)" || {
    local escaped
    escaped="$(echo "$bob_output" | sed 's/"/\\"/g' | tr -d '\n')"
    echo "{\"ok\":false,\"error\":\"Bob Shell failed: $escaped\"}"
    return
  }
  log "Bob Shell finished."

  # ── 2. Find the script Bob wrote ────────────────────────────────────────────
  local scripts_dir="$WORKSPACE/specs/scripts"
  local new_script
  new_script="$(find "$scripts_dir" -name "*.json" \
    -newer "$WORKSPACE/specs/free-roam-spec.md" \
    -not -name "README*" 2>/dev/null | tail -1)"

  if [ -z "$new_script" ]; then
    echo '{"ok":false,"error":"Bob finished but no new script file was found"}'
    return
  fi
  log "Script written: $new_script"

  # ── 3. Rebuild client container ─────────────────────────────────────────────
  log "Rebuilding client container..."
  docker-compose -f "$COMPOSE_FILE" build client 2>&1 | \
    while IFS= read -r line; do log "  docker: $line"; done

  # ── 4. Restart client container ─────────────────────────────────────────────
  log "Restarting client container..."
  docker-compose -f "$COMPOSE_FILE" up -d client 2>&1 | \
    while IFS= read -r line; do log "  docker: $line"; done

  # ── 5. Return script JSON ────────────────────────────────────────────────────
  local script_json
  script_json="$(cat "$new_script")"
  printf '{"ok":true,"script":%s}\n' "$script_json"
  log "Done. Returned: $(echo "$script_json" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
}

# ─── Socket server ────────────────────────────────────────────────────────────
rm -f "$SOCKET_PATH"

log "Listening on $SOCKET_PATH"
log "Workspace: $WORKSPACE"
log "Press Ctrl+C to stop."

# Write the handler + all variables into a temp script that socat executes.
# This avoids relying on export -f (bash function export) which is unreliable
# across socat's exec boundary.
HANDLER_SCRIPT="$(mktemp /tmp/bob-handler-XXXXXX.sh)"
chmod +x "$HANDLER_SCRIPT"

cat > "$HANDLER_SCRIPT" << HANDLER_EOF
#!/usr/bin/env bash
BOB_API_KEY="$BOB_API_KEY"
COMPOSE_FILE="$COMPOSE_FILE"
WORKSPACE="$WORKSPACE"
SOCKET_PATH="$SOCKET_PATH"
export BOB_API_KEY

log() { echo "[bob-host-agent] \$*" >&2; }

$(declare -f handle_request)

handle_request
HANDLER_EOF

# Clean up temp script on exit
trap 'rm -f "$HANDLER_SCRIPT"; rm -f "$SOCKET_PATH"' EXIT INT TERM

socat UNIX-LISTEN:"$SOCKET_PATH",fork,mode=666 \
  EXEC:"bash $HANDLER_SCRIPT",nofork
