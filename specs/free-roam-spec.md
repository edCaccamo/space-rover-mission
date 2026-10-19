# Free Roam Spec

## Feature Name

Free Roam

## Game Mode ID

5

## Description

Type plain-English rover instructions and execute them in open space without a physical game board.

## Board Required

no

---

## Calibration Constants

These values are used to convert human-readable units into millisecond durations for the rover firmware.

| Constant | Value | Usage |
| --- | --- | --- |
| `ms_per_degree` | 8 | `durationMs = degrees × 8` for turns |
| `ms_per_cm` | 18 | `durationMs = distance_cm × 18` for forward/backward |
| `max_step_duration_ms` | 10000 | Cap on any single step's `durationMs` |
| `max_duration_ms` | 30000 | Cap on total script duration (sum of all steps) |

---

## Safety Rules

- Any single step's `durationMs` must not exceed `max_step_duration_ms` (10 000 ms).
- The sum of all `durationMs` values in a script must not exceed `max_duration_ms` (30 000 ms).
- Scripts that would take the rover beyond `soft_boundary_radius_cm` (150 cm) from its start position trigger a boundary warning in the UI. This is enforced client-side via dead-reckoning simulation.

---

## Script Format

Bob writes scripts as JSON files to `specs/scripts/`. Each file has this shape:

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

**Stop rule:** `{ "command": "S", "durationMs": 0 }` must appear between every two consecutive motion steps and at the end of every script. The firmware keeps driving until it receives `S`; omitting it causes the rover to blend motions instead of stopping cleanly between them.

---

## UI Labels

- `execute_button_label`: Execute
- `cancel_button_label`: Stop
- `status_executing`: Executing rover script...
- `status_completed`: Rover script completed.
- `status_cancelled`: Rover script cancelled.
- `warning_boundary`: Warning: this script may take the rover near the boundary.
