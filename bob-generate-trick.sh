#!/usr/bin/env bash
################################################################################
# bob-generate-trick.sh
#
# Ubuntu end-to-end workflow:
#   1. (On internet) Run Bob Shell to generate a new rover trick script
#   2. Rebuild the client Docker image to bundle the new script
#   3. Switch Wi-Fi from internet → OL_DEMO (rover network)
#   4. Start the full stack
#   5. Wait for rover reachability, then open the browser
#
# Prerequisites:
#   - Bob Shell installed: curl -fsSL https://bob.ibm.com/download/bobshell.sh | bash
#   - Bob Shell authenticated (first run opens browser for IBMid login)
#   - docker / docker compose v2
#   - NetworkManager with OL_DEMO profile already saved
#   - xdg-open (standard on Ubuntu desktop)
#
# Usage:
#   chmod +x bob-generate-trick.sh
#   ./bob-generate-trick.sh
#   ./bob-generate-trick.sh "do a figure 8 then stop"   # non-interactive
################################################################################

set -euo pipefail

COMPOSE_FILE="services/docker-compose.yml"
ROVER_IP="192.168.0.115"
ROVER_PORT="5045"
ROVER_WIFI="OL_DEMO"          # fixed — the rover router SSID never changes
BROWSER_URL="http://localhost:3000"

# Optional: name of the Wi-Fi interface. Auto-detected if blank.
WIFI_IFACE=""

# ─── Load config from services/.env ───────────────────────────────────────────
# Each user maintains their own services/.env (gitignored).
# Copy services/.env.example → services/.env and fill in your values.
ENV_FILE="$(dirname "$0")/services/.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a; source "$ENV_FILE"; set +a
fi

if [ -z "${BOB_API_KEY:-}" ]; then
  echo "  ✗ BOB_API_KEY is not set."
  echo "    Copy services/.env.example → services/.env and add your key."
  echo "    Get a key at https://bob.ibm.com (API Keys section)."
  exit 1
fi
if [ -z "${INTERNET_WIFI:-}" ]; then
  echo "  ✗ INTERNET_WIFI is not set."
  echo "    Add INTERNET_WIFI=<your-ssid> to services/.env"
  exit 1
fi

export BOB_API_KEY

# ─── Colours ──────────────────────────────────────────────────────────────────
COL_RESET="\033[0m"
COL_GREEN="\033[0;32m"
COL_YELLOW="\033[0;33m"
COL_CYAN="\033[0;36m"
COL_BOLD="\033[1m"

hr() { echo -e "${COL_CYAN}══════════════════════════════════════════════${COL_RESET}"; }
ok() { echo -e "  ${COL_GREEN}✓${COL_RESET} $*"; }
info() { echo -e "  ${COL_YELLOW}→${COL_RESET} $*"; }

# ─── Spinner ──────────────────────────────────────────────────────────────────
spinner() {
  local msg="$1" pid="$2"
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s " "${frames:$((i % ${#frames})):1}" "$msg"
    sleep 0.1
    i=$((i + 1))
  done
  printf "\r"
}

# ─── Detect Wi-Fi interface ────────────────────────────────────────────────────
detect_wifi_iface() {
  if [ -n "$WIFI_IFACE" ]; then
    echo "$WIFI_IFACE"
    return
  fi
  # Pick the first active 802-11-wireless device
  nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}'
}

# ─── Step 1: Generate script with Bob CLI ─────────────────────────────────────
hr
echo -e "  ${COL_BOLD}Step 1: Generate rover trick with Bob${COL_RESET}"
hr

# Accept prompt as CLI arg, or ask interactively
if [ "${1:-}" != "" ]; then
  TRICK_PROMPT="$1"
else
  echo ""
  echo -e "  Describe the trick you want the rover to perform."
  echo -e "  Examples: \"do a figure 8\", \"spin right 3 times then reverse\""
  echo ""
  printf "  Your description: "
  read -r TRICK_PROMPT
fi

if [ -z "$TRICK_PROMPT" ]; then
  echo "  ✗ No description provided. Exiting."
  exit 1
fi

echo ""
info "Asking Bob: \"$TRICK_PROMPT\""
echo ""

# Bob Shell non-interactive mode: bob -p "prompt"
# Must be run from the repo root so Bob loads .bob/rules/ and the rover-spec
# skill automatically. The rover-spec skill and bob-bridge-strict rules guide
# Bob to write only the correct files and nothing else.
# First-time use requires: bob --accept-license -p "..."
bob -p "Generate a rover trick script for this description: $TRICK_PROMPT"

echo ""
ok "Bob finished generating the script."

# ─── Step 2: Rebuild the client ───────────────────────────────────────────────
hr
echo -e "  ${COL_BOLD}Step 2: Rebuilding client container${COL_RESET}"
hr
echo ""
info "Running: docker compose -f $COMPOSE_FILE build client"
docker compose -f "$COMPOSE_FILE" build client
echo ""
ok "Client image rebuilt."

# ─── Step 3: Switch Wi-Fi to OL_DEMO ─────────────────────────────────────────
hr
echo -e "  ${COL_BOLD}Step 3: Switching Wi-Fi to $ROVER_WIFI${COL_RESET}"
hr
echo ""

IFACE="$(detect_wifi_iface)"
if [ -z "$IFACE" ]; then
  echo "  ✗ Could not detect a Wi-Fi interface."
  echo "    Connect to $ROVER_WIFI manually, then re-run from Step 4:"
  echo "    docker compose -f $COMPOSE_FILE up -d"
  exit 1
fi

info "Connecting $IFACE to $ROVER_WIFI ..."
nmcli device wifi connect "$ROVER_WIFI" ifname "$IFACE" 2>/dev/null \
  || nmcli connection up "$ROVER_WIFI" ifname "$IFACE"

# Give NetworkManager a moment to assign an IP
sleep 3

CURRENT_SSID="$(nmcli -t -f active,ssid dev wifi | awk -F: '/^yes/{print $2; exit}')"
if [ "$CURRENT_SSID" != "$ROVER_WIFI" ]; then
  echo ""
  echo -e "  ${COL_YELLOW}Warning:${COL_RESET} connected SSID is '${CURRENT_SSID}' — expected '${ROVER_WIFI}'."
  echo "  Switch manually if needed before the rover will be reachable."
else
  ok "Connected to $ROVER_WIFI."
fi

# ─── Step 4: Start the stack ──────────────────────────────────────────────────
hr
echo -e "  ${COL_BOLD}Step 4: Starting containers from cache${COL_RESET}"
hr
echo ""
docker compose -f "$COMPOSE_FILE" up -d
ok "Containers started."

# ─── Step 5: Wait for rover reachability ──────────────────────────────────────
hr
echo -e "  ${COL_BOLD}Step 5: Waiting for rover to be reachable${COL_RESET}"
hr
echo ""

(
  # Poll ping from inside the client container
  until docker exec services-client-1 ping -c1 -W1 "$ROVER_IP" > /dev/null 2>&1; do
    sleep 2
  done
  # Poll rover WebSocket
  until docker exec services-gameservice-1 \
    curl -sf --max-time 2 \
      -H "Upgrade: websocket" \
      -H "Connection: Upgrade" \
      -H "Sec-WebSocket-Key: test" \
      -H "Sec-WebSocket-Version: 13" \
      "http://$ROVER_IP:$ROVER_PORT/" > /dev/null 2>&1; do
    sleep 2
  done
) &
WAIT_PID=$!
spinner "Waiting for rover ping and WebSocket ..." "$WAIT_PID"
wait "$WAIT_PID"
ok "Rover is reachable."

# ─── Done ─────────────────────────────────────────────────────────────────────
hr
echo ""
echo -e "  ${COL_GREEN}${COL_BOLD}All steps complete!${COL_RESET}"
echo ""
echo -e "  Your new trick is in the Free Roam dropdown at:"
echo -e "  ${COL_CYAN}${BROWSER_URL}${COL_RESET}"
echo ""

# Open the browser if xdg-open is available
if command -v xdg-open &>/dev/null; then
  xdg-open "$BROWSER_URL" &>/dev/null &
  ok "Browser opened."
fi

echo ""
hr
