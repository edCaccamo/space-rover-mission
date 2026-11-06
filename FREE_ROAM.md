# Free Roam Mode

Free Roam is a new game mode added to the Space Rover Mission that lets you drive the rover freely in open space — no physical game board required. Instead of navigating planets and avoiding obstacles on a map, you describe what you want the rover to do and it just does it.

---

## How it differs from the original game

| | Original Game | Free Roam |
|---|---|---|
| **Board** | Required — physical LED game board with RFID tiles | Not used — rover runs in open space |
| **Control** | Hand gestures via webcam (OpenCV) | Pre-authored or Bob-generated scripts, picked and run from the browser |
| **Objective** | Navigate the map, collect planets, avoid obstacles | Execute choreographed tricks and movements |
| **Game modes** | Classic, Planet Hop, Guided, Sudden Death | Free Roam (mode 5) |
| **Scoring** | Health and score tracked against the board | No scoring — pure movement execution |

The rover hardware is identical. The game service still routes all commands over WebSocket. The difference is that the game board is replaced by a mock service (`mockboard`) that handles only the startup handshake, and all movement decisions come from a pre-authored script rather than real-time gesture input. Free Roam has no time limit.

The standard game modes are unchanged: `services/docker-compose.yml` is the same as upstream and expects the real game board.

---

## What is spec-driven development?

Free Roam was built using **spec-driven development** — the feature behaviour is defined in a Markdown spec file before any code is written, and an AI coding assistant (Bob) reads that spec to author rover scripts on demand.

The spec lives at [`specs/free-roam-spec.md`](specs/free-roam-spec.md) and defines:
- **Calibration constants** — how milliseconds map to real-world distance and angle (`18 ms/cm`, `8 ms/degree`)
- **Safety rules** — max step duration (10 s), max total script duration (30 s), soft boundary radius (150 cm)
- **Script format** — the `{name, description, steps}` JSON shape that Bob writes and the client executes

When you describe a trick to Bob in plain English (e.g. _"go forward then do a circle"_), Bob reads the spec and translates your description into a `CommandScript` JSON file — a sequence of timed commands (`F`, `B`, `L`, `R`, `S`) that the rover executes in order. You can describe the trick in Bob IDE or directly in the browser, which talks to Bob Shell through the `bob-bridge` service.

```
You describe a trick (Bob IDE, or the browser via bob-bridge → Bob Shell)
        ↓
Bob reads specs/free-roam-spec.md (calibration constants)
        ↓
Bob writes a script JSON to specs/scripts/
        ↓
Script appears in the browser dropdown (loaded at runtime from bob-bridge)
        ↓
F / B / L / R / S commands sent over WebSocket → Game Service → Rover
```

The `specs/` directory is the source of truth. Changing a calibration constant in the spec changes how Bob authors every future script, and any script in `specs/scripts/` is available in the browser without rebuilding or restarting containers.

---

## Initial setup

### 1. Clone the repository

```bash
git clone https://github.com/OpenLiberty/space-rover-mission.git
cd space-rover-mission
```

### 2. Open the repo in Bob IDE

Open the `space-rover-mission` folder in Bob. Bob will automatically detect the workspace and load the rover-spec skill from `.bob/skills/rover-spec/SKILL.md`.

### 3. Add your Bob API key

Browser-based trick generation needs a Bob API key. Generate one at https://bob.ibm.com (API Keys section), then:

```bash
cp services/.env.example services/.env
```

Edit `services/.env` and set `BOB_API_KEY`. The file is gitignored — never commit your key.

`services/.env` is **optional**. Without it the stack still starts, and Free Roam can run every existing script. Only **Generate a new trick with Bob** is unavailable, and the browser tells you the key is missing.

### 4. Build the Docker images (requires internet)

Do this once on IBM Wi-Fi or any internet connection. You only need to repeat this if the service code changes (not when `specs/` changes).

```bash
cd services
podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml build
```

---

## Authoring a new script with Bob

There are two ways to ask Bob for a new trick. Both use the same rover-spec skill and produce the same result: a script JSON file in `specs/scripts/`.

Examples of what you can say:
- _"Go forward and then do a circle"_
- _"Do a figure 8"_
- _"Spin right for 3 seconds then reverse"_
- _"Do a three point turn"_

### Option 1: Bob IDE

With the repo open in Bob IDE, describe the rover behaviour in chat. Bob reads [`specs/free-roam-spec.md`](specs/free-roam-spec.md) and writes the JSON for you.

### Option 2: Describing a trick in the browser

In the Free Roam screen, open **Generate a new trick with Bob**, type a description, and click **Generate**. The browser sends your description to the `bob-bridge` service (`http://localhost:4000/generate`), which runs Bob Shell inside its container. Bob Shell uses the same rover-spec skill and writes the script to `specs/scripts/`. The generated script is then shown in the browser, where you can run it on the rover.

This requires:
- A Bob API key in `services/.env` (see [Initial setup](#initial-setup))
- Internet access from your Mac, since Bob Shell calls the Bob API (see [Known limitations](#known-limitations))

Generation can take a while. Bob Shell has a 10-minute timeout.

### What Bob does

1. Reads [`.bob/rules/bob-bridge-strict.md`](.bob/rules/bob-bridge-strict.md) and treats your description only as a description of rover movement
2. Translates it into a valid script JSON using the calibration constants in the spec
3. Writes the file to `specs/scripts/<name>.json` — the only place Bob is allowed to write

### The specs directory is the source of truth

The spec and the scripts live in [`specs/`](specs/). The `bob-bridge` container mounts the repo as `/workspace` **read-only**, with `specs/scripts/` overlaid as the only **read-write** path. Bob Shell can read the spec, rules, and skill, but can only write to `specs/scripts/`. The client loads the script list from `bob-bridge` at runtime (`GET /scripts`), reading whatever is in `specs/scripts/` at that moment. This means:

- You do **not** need to rebuild the client or run `docker compose down` and `up` when scripts or specs change.
- A script added by Bob (from the IDE or the browser), or edited by hand, shows up the next time the client loads its script list. Reload the page if it doesn't appear.

See [`specs/scripts/README.md`](specs/scripts/README.md) for the full JSON schema and calibration reference.

### Pre-authored scripts

The repo ships with a set of ready-made scripts in [`specs/scripts/`](specs/scripts/), such as Move Forward, Turn Left, Three Point Turn, Figure 8, Donut, and Forward Then Circle. Whatever is in that directory appears in the dropdown.

---

## Running Free Roam

Use the browser UI to pick, generate, and run scripts.

#### 1. Connect to the rover network

The rover is only reachable on the OL_DEMO network. To also keep internet access for Bob, connect **Ethernet to OL_DEMO** and **Wi-Fi to a public network** (see [Known limitations](#known-limitations)). If you only want to run existing scripts, being on OL_DEMO alone is enough.

#### 2. Start the stack

Free Roam uses an extra compose file, `services/docker-compose.freeroam.yml`, layered on top of the standard one. It adds `mockboard` (so no game board is needed) and `bob-bridge` (which lists tricks and generates new ones):

```bash
cd services
podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml up -d --build
```

For the standard game with the real board, use the plain file as before: `podman-compose up -d`. Free Roam is blocked on the start screen in that case, because `bob-bridge` is not running and there are no tricks to list.

#### 3. Open the browser

Go to **http://localhost:3000**.

#### 4. Enter your name and select Free Roam

- Enter your player name in the text field
- Select **Free Roam** from the game mode dropdown
- Hit **Begin mission**

#### 5. Execute a script

The in-game screen shows:
- A **script dropdown** — every script currently in `specs/scripts/`, listed by name
- The selected script's **description** below the dropdown
- An **Execute** button — sends the script to the rover (shows _"Executing rover script..."_ while running, _"Rover script completed."_ when done)
- A **Stop** button — immediately halts the rover mid-script
- A **Generate a new trick with Bob** panel — describe a trick in plain English and Bob writes it for you (see [Option 2](#option-2-describing-a-trick-in-the-browser))
- An **End mission** button — exits back to the home screen

---

## Stopping the stack

```bash
cd services
podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml down
```

---

## Troubleshooting

### Mock mode (no physical rover)

If you don't have a rover available, you can verify the UI and script execution end-to-end with the simulated rover. `docker-compose-test.yml` (unchanged from upstream) contains `mockrover` and `mockboard`; layer the Free Roam file on top to add `bob-bridge`:

1. Point the game service at the mocks: in `services/game/src/main/webapp/META-INF/microprofile-config.properties`, comment out the *Physical Hardware* block and uncomment the *Test* block (see [`services/mock/README.md`](services/mock/README.md)). Revert this before using real hardware.
2. Start the stack:

```bash
cd services
podman-compose -f docker-compose-test.yml -f docker-compose.freeroam.yml up -d --build
```

The mock rover logs every command it receives instead of driving hardware. Watch them arrive:

```bash
podman logs -f services_mockrover_1
```

For a Forward Then Circle script you would see:
```
Message Recieved: F
Message Recieved: S
Message Recieved: L
Message Recieved: S
```
(The mock's log text really is spelled "Recieved".)

Use mock mode to confirm your script logic is correct before running on the physical rover.

---

## Known limitations

- **Rover movements are approximate.** The calibration constants (`18 ms/cm`, `8 ms/degree`) are tuned to the specific rover hardware and surface. On different floors or battery levels the rover may overshoot or undershoot. If a turn or distance is off, ask Bob to adjust the `durationMs` values and re-run.

- **Circle and turning angles may not be exact.** A 360° circle requires the spin timing to be dialled in per-rover. The current values are tuned empirically — if the rover doesn't complete a full rotation, increase the `L`/`R` `durationMs` on the relevant script step.

- **OL_DEMO has no internet access, so a single Wi-Fi connection can't do both jobs.** The rover is only reachable on OL_DEMO, but generating a trick with Bob requires reaching the Bob API over the internet. If your Mac is on OL_DEMO Wi-Fi only, the rover works but **Generate** will fail. If you're on a public network only, Bob works but the rover is unreachable.

  **Fix: use two connections at once.** Connect your Mac to OL_DEMO over **Ethernet**, and connect **Wi-Fi** to a public network. The rover traffic goes over Ethernet and Bob's traffic goes over Wi-Fi, so you can generate tricks and run them without switching networks.

- **The game service will hang if started without a route to the rover.** The game service connects to the rover at `192.168.0.115` on startup. If your Mac has no connection to OL_DEMO when `podman-compose up` runs, the service will wait indefinitely for the rover connection. Connect to OL_DEMO first.

- **The rover is started in Classic mode, not mode 5.** The rover firmware (NodeMCU) only recognises game modes `1`-`4` as "game started"; until it does, it ignores movement commands and its lights keep blinking. The game service therefore sends `1` to the rover when you pick Free Roam (see the `START_GAME` case in `GameServer.java`). The board and the web app still see mode `5`. To have the rover receive a real `5`, reflash it with `devices/space-rover/src/SpaceRover_NodeMCU.ino`, which already accepts `5`, then remove the mapping in `GameServer.java`.

- **MongoDB is pinned to 4.4.** The leaderboard uses the old `mongo-java-driver` 3.12, which cannot connect to the current `mongo:latest` (9.x): the leaderboard stalls with `Command buildInfo requires authentication` and the game service never reports ready. `services/docker-compose.yml` therefore uses `mongo:4.4`. If you switch Mongo versions, clear the old data first: `podman-compose down`, then `podman unshare rm -rf ~/mongo/data/*`.

