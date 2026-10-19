# Rover Scripts

This folder holds Bob-authored rover scripts for Free Roam mode.

## JSON Schema

Each file is a script JSON with the following shape:

```json
{
  "name": "string",
  "description": "string",
  "steps": [
    { "command": "F" | "B" | "L" | "R" | "S", "durationMs": number }
  ]
}
```

| Command | Meaning |
| --- | --- |
| `F` | Move forward |
| `B` | Move backward |
| `L` | Spin left (rotate left in place) |
| `R` | Spin right (rotate right in place) |
| `S` | Stop — always use `durationMs: 0` |

**Stop rule:** Always include `{ "command": "S", "durationMs": 0 }` between every two consecutive motion steps and at the end of every script.

## Calibration Constants (from `specs/free-roam-spec.md`)

| Constant | Value | Usage |
| --- | --- | --- |
| `ms_per_degree` | 8 | `durationMs = degrees × 8` for turns |
| `ms_per_cm` | 18 | `durationMs = distance_cm × 18` for forward/backward |
| `max_step_duration_ms` | 10000 | Each individual step must not exceed 10 000 ms |
| `max_duration_ms` | 30000 | Total script duration must not exceed 30 000 ms |

## Authoring a New Script

Describe the rover behaviour you want in plain English, either in Bob IDE or in the **Generate a new trick with Bob** panel in the browser.
Bob will:
1. Read `.bob/rules/bob-bridge-strict.md` and treat your description only as a description of rover movement
2. Read `specs/free-roam-spec.md` for the calibration constants
3. Translate your description into a valid script JSON
4. Write the file to `specs/scripts/<kebab-case-name>.json`

That is the only file Bob writes. The client loads the script list from bob-bridge (`GET /scripts`) at runtime, so the script appears in the Free Roam dropdown without a rebuild or restart. Reload the page if it doesn't show up.

Scripts can also be added or edited by hand. Any valid script JSON in this folder is picked up automatically.

## Running a Script on the Physical Rover

See [`FREE_ROAM.md`](../../FREE_ROAM.md) for network setup (OL_DEMO), starting the stack, and executing scripts from the browser.
