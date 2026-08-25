# Free Roam Mode

Free Roam is a new game mode added to the Space Rover Mission that lets you drive the rover freely in open space — no physical game board required. Instead of navigating planets and avoiding obstacles on a map, you describe what you want the rover to do and it just does it.

---

## How it differs from the original game

| | Original Game | Free Roam |
|---|---|---|
| **Board** | Required — physical LED game board with RFID tiles | Not used — rover runs in open space |
| **Control** | Hand gestures via webcam (OpenCV) | Plain-English commands typed in the browser, or automated scripts |
| **Objective** | Navigate the map, collect planets, avoid obstacles | Execute choreographed tricks and movements |
| **Game modes** | Classic, Planet Hop, Guided, Sudden Death | Free Roam (mode 5) |
| **Scoring** | Health and score tracked against the board | No scoring — pure movement execution |

The rover hardware is identical. The game service still routes all commands over WebSocket. The difference is that the game board is replaced by a mock service that handles only the startup handshake, and all movement decisions come from a pre-authored script rather than real-time gesture input.

---

## What is spec-driven development?

Free Roam was built using **spec-driven development** — the feature behaviour is defined in a Markdown spec file before any code is written, and an AI coding assistant (Bob) reads that spec to author rover scripts on demand.

The spec lives at [`specs/free-roam-spec.md`](specs/free-roam-spec.md) and defines:
- The **move vocabulary** — the set of named moves the rover understands (`forward`, `spin_left`, `turn_right`, etc.)
- **Calibration constants** — how milliseconds map to real-world distance and angle (`18 ms/cm`, `8 ms/degree`)
- **Safety rules** — max step duration (10 s), max total script duration (30 s), soft boundary radius (150 cm)

When you describe a trick to Bob in plain English (e.g. _"go forward then do a circle"_), Bob reads the spec and translates your description into a `CommandScript` JSON file — a sequence of timed commands (`F`, `B`, `L`, `R`, `S`) that the rover executes in order.

```
You describe a trick in Bob IDE
        ↓
Bob reads specs/free-roam-spec.md (move vocabulary + calibration)
        ↓
Bob writes a CommandScript JSON to specs/scripts/ and services/client/src/specs/scripts/
        ↓
Script appears in the browser dropdown or is run via run-trick.sh
        ↓
F / B / L / R / S commands sent over WebSocket → Game Service → Rover
```

The spec is the source of truth. Changing a calibration constant in the spec changes how Bob authors every future script.

---

## Running Free Roam — two modes

### Mode A: Browser UI (mock or real hardware)

Use this when you want to interactively pick and run scripts from the web interface.

#### Step 1 — Build and start the stack

**Without hardware (mock rover):**
```bash
docker compose -f services/docker-compose-test.yml up --build
```

This starts four containers:

| Container | Role |
|---|---|
| `client` | Browser UI at http://localhost:3000 |
| `gameservice` | WebSocket hub — routes commands between browser and rover |
| `mockrover` | Simulates the rover — logs every command it receives |
| `mockboard` | Simulates the game board startup handshake |

**With real hardware (rover on OL_DEMO network):**
```bash
docker compose -f services/docker-compose.yml build   # once, on internet
# — switch Mac Wi-Fi to OL_DEMO —
docker compose -f services/docker-compose.yml up -d
```

#### Step 2 — Open the browser

Go to **http://localhost:3000**, enter a player name, and hit **Start Mission**. The game mode is automatically set to **Free Roam**.

#### Step 3 — Pick a script and execute

The in-game screen shows a script dropdown. Select any of the pre-authored scripts, read the description, and hit **Execute**. Hit **Stop** at any time to immediately halt the rover.

| Script | What it does |
|---|---|
| Move Forward | Drive straight forward ~100 cm |
| Move Backward | Drive straight backward ~100 cm |
| Turn Left | Forward → pivot left 90° → forward |
| Turn Right | Forward → pivot right 90° → forward |
| Three Point Turn | Forward → pivot 180° → reverse |
| Figure 8 | Full left circle → full right circle |
| Donut | Spin left 3 full rotations |
| Forward Then Circle | Drive forward ~100 cm → spin one full rotation |

#### Step 4 — Verify commands (mock mode)

Watch the commands arrive on the mock rover in real time:
```bash
docker logs -f services-mockrover-1
```

---

### Mode B: Automated script via `run-trick.sh`

Use this to run the **Forward Then Circle** trick on the physical rover end-to-end from a single command, with no browser interaction.

#### Pre-requisite — build images once (requires internet)

Do this on IBM Wi-Fi or any internet connection. You only need to repeat this if the code changes.

```bash
docker compose -f services/docker-compose.yml build
```

#### Running the trick

1. Switch your Mac Wi-Fi to **OL_DEMO** (the rover's private network)
2. Run:
```bash
./run-trick.sh
```

The script does the following automatically:

| Step | What happens |
|---|---|
| **1** | Starts the containers from the local Docker cache — no internet required |
| **2** | Spins with a live indicator, polling ping and WebSocket until the rover responds |
| **3** | Pings the rover from inside the client container to confirm network reachability |
| **4** | Probes the rover WebSocket from inside the game service container — confirms `101 Switching Protocols` |
| **5** | Sends the Forward Then Circle script over the game service WebSocket with live countdown output |

Example terminal output:
```
══════════════════════════════════════════════
  Step 1: Starting containers from cache
══════════════════════════════════════════════
  ✓ Containers started.

══════════════════════════════════════════════
  Step 2: Waiting for rover connectivity
  (switch your Mac to OL_DEMO now if not done)
══════════════════════════════════════════════
  ⠸ Waiting for ping and WebSocket to rover...
  ✓ Rover is reachable and WebSocket is live.

══════════════════════════════════════════════
  Step 3: Executing Forward Then Circle
  (forward 4800ms → stop → spin 4400ms → stop)
══════════════════════════════════════════════
  ✓ Connected, starting game...
  ✓ Game started (Free Roam mode 5)
  → Sending FORWARD...
  ⏱  Moving forward — 3s remaining...
  ✓  Moving forward done.
  → Sending SPIN LEFT...
  ⏱  Spinning circle — 2s remaining...
  ✓  Spinning circle done.
  → Sending STOP...

══════════════════════════════════════════════
  ✓ Forward Then Circle complete!
══════════════════════════════════════════════
```

---

## Authoring a new script with Bob

Open Bob IDE and describe the rover behaviour you want in plain English. Bob will read the spec and write the JSON for you.

Examples:
- _"Go forward and then do a circle"_
- _"Do a figure 8"_
- _"Spin right for 3 seconds then reverse"_

Bob will:
1. Translate your description into a valid `CommandScript` JSON using the calibration constants
2. Write the file to `specs/scripts/<name>.json`
3. Copy it to `services/client/src/specs/scripts/<name>.json`
4. Register it in `services/client/src/specs/scripts/index.ts` so it appears in the browser dropdown

Rebuild the client to pick up the new script:
```bash
docker compose -f services/docker-compose.yml build client
```

See [`specs/scripts/README.md`](specs/scripts/README.md) for the full JSON schema and calibration reference.

---

## Stopping the stack

```bash
docker compose -f services/docker-compose.yml down
# or for mock mode:
docker compose -f services/docker-compose-test.yml down
```
