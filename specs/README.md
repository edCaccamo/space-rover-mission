# Specs

This folder stores the Markdown specifications that drive rover feature implementation.

## Workflow

1. A user describes the rover behaviour they want in Bob.
2. Bob fills out [`TEMPLATE.md`](specs/TEMPLATE.md) with the requested behaviour details.
3. Bob reads the completed spec file from `specs/`.
4. Bob injects the matching code into the Java game service and the React client.

The spec is the single source of truth for:
- game mode metadata
- move vocabulary
- calibration constants
- LLM prompt rules
- safety limits
- UI labels
- whether a physical board is required

## How to use

1. Copy [`TEMPLATE.md`](specs/TEMPLATE.md) to a new spec file in this folder.
2. Ask Bob to fill in the template based on the rover behaviour you want.
3. Review the completed spec and confirm the values.
4. Ask Bob to read that spec and apply the implementation changes.

## Included example

[`free-roam-spec.md`](specs/free-roam-spec.md) is a complete example for the Free Roam feature. It shows the format Bob should produce before generating code changes in the backend and frontend.

## Running Without Hardware

You can run the full stack without a physical rover or game board using the built-in mock services.

**Step 1 — Start all services:**
```bash
cd services
docker compose -f docker-compose-test.yml up
```
This starts the client, game service, leaderboard, MongoDB, Prometheus, Grafana, and two mock containers (`mockrover` and `mockboard`) that simulate the physical hardware. The game service automatically points at the mock services — no config editing needed.

**Step 2 — Open the browser:**

Go to [http://localhost:3000](http://localhost:3000)

**Step 3 — Start a Free Roam session:**

1. Enter a player name
2. Select **Free Roam** from the game mode dropdown
3. Hit **Start**

**Step 4 — Execute a script:**

The in-game screen shows a **Select a rover script** dropdown.
Pick a script and hit **Execute**. The `usePromptControls` hook replays the
`F/B/L/R/S` commands over the WebSocket with correct timing.

**Step 5 — Watch the mock rover receive commands:**
```bash
docker logs -f services-mockrover-1
```
You will see each command logged as it arrives, for example:
```
Message Received: L
Message Received: S
```

## Authoring New Scripts with Bob

To add a new rover script:

1. Open Bob and describe the rover behaviour you want — for example:
   _"drive forward 50 cm, turn right 90 degrees, then do a figure 8"_
2. Bob activates the `rover-spec` skill, reads `specs/free-roam-spec.md` for the
   move vocabulary and calibration constants, then writes:
   - `specs/scripts/<name>.json` — the canonical script file
   - `services/client/src/specs/scripts/<name>.json` — the client-side copy
   - Adds an import + entry to `services/client/src/specs/scripts/index.ts`
3. Rebuild the client (`docker compose build client`) — the new script appears
   in the Free Roam dropdown immediately.

