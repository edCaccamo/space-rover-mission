# Rover Scripts

Pre-authored `CommandScript` JSON files for Free Roam mode. Each file is served at runtime by the `bob-bridge` sidecar via `GET /scripts` and appears in the Free Roam script dropdown.

## Schema

```json
{
  "name": "string",
  "description": "string",
  "steps": [
    { "command": "F" | "B" | "L" | "R" | "S", "durationMs": number }
  ]
}
```

| Command | Action |
|---------|--------|
| `F` | Move forward |
| `B` | Move backward |
| `L` | Spin left in place |
| `R` | Spin right in place |
| `S` | Stop (`durationMs` must be `0`) |

## Calibration constants

| Constant | Value |
|----------|-------|
| `ms_per_cm` | 18 |
| `ms_per_degree` | 8 |
| `max_step_duration_ms` | 10000 |
| `max_duration_ms` | 30000 |
| `soft_boundary_radius_cm` | 150 |

## Adding a new script

Describe the trick to Bob in plain English. Bob will read `specs/free-roam-spec.md`, translate it into a valid `CommandScript`, write the JSON here, and register it in the bob-bridge scripts directory automatically.

After Bob writes a new script, the bob-bridge picks it up immediately (no rebuild needed) — just refresh the browser dropdown.
