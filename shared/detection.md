# Lumen — session detection rules (shared spec)

Both the macOS and Windows implementations MUST follow these rules so behavior is identical across platforms. The goal: **"awake" means real agent work is happening, not merely that an app is open.**

## Decision output

Each poll produces a boolean `shouldStayAwake` plus a human-readable `reason`. The platform layer maps `true → keep awake (lid closed)` and `false → allow normal sleep`.

## Inputs

1. **Manual override** (highest priority)
   - `forceOff` → `false` (reason: "manual: allow sleep").
   - `forceOn` → `true` (still subject to safety governors below).

2. **Session-log activity** — active if any watched session log was modified within `graceMinutes` (default **10**):
   - **Claude Code:** `~/.claude/projects/**/*.jsonl` (macOS/Linux), `%USERPROFILE%\.claude\projects\**\*.jsonl` (Windows).
   - **Codex:** `~/.codex/sessions/**/*.jsonl` and `~/.codex/*.sqlite-wal` (optional, off by default because it churns while idle).

3. **Process + CPU triggers** (configurable list, default off unless enabled):
   - Match by executable name (exact) against the user's list (e.g. `ollama`, `docker`, `node`, `python`, `cursor`).
   - Require sustained CPU ≥ `cpuThresholdPercent` (default **40%**) over the sample to count as "working".

`shouldStayAwake = manual OR sessionActive OR processActive`, then safety governors can force it to `false`.

## Safety governors (can only turn OFF)

Applied in order; the first that fires wins and sets `false`:

1. **Critical battery** — on battery and level ≤ `criticalBatteryPercent` (default **10%**) → force sleep.
2. **Battery floor** — on battery and level ≤ `batteryFloorPercent` (default **20%**) → allow sleep.
3. **AC-only mode** (optional) — if enabled and on battery → allow sleep.
4. **Thermal release** — if thermal pressure is Serious/Critical (macOS) or equivalent (Windows) → allow sleep.
5. **Hard cap** — continuous awake time ≥ `maxHours` (default **8h**) → allow sleep until the next idle period re-arms.

## State machine

- Keep a persisted `onSince` timestamp (set on the first `true`, cleared on any `false` caused by inactivity).
- `capped` latch: once the hard cap fires, stay `false` until a genuine idle period (no activity) clears it.
- On process/app crash or reboot: the platform layer MUST restore the OS default (allow sleep) so a stuck override cannot brick sleep forever.

## Defaults (config schema keys)

| key | default | meaning |
|---|---|---|
| `graceMinutes` | 10 | keep awake this long after last activity |
| `batteryFloorPercent` | 20 | below this on battery → sleep |
| `criticalBatteryPercent` | 10 | below this on battery → force sleep |
| `maxHours` | 8 | hard cap on continuous awake |
| `cpuThresholdPercent` | 40 | CPU bar for process triggers |
| `acOnly` | false | only keep awake on charger |
| `enableProcessTriggers` | false | use the process list |
| `processList` | `[]` | executable names to watch |
| `watchClaude` | true | watch Claude Code session logs |
| `watchCodex` | true | watch Codex session logs |
| `pollSeconds` | 15 | how often to evaluate |

Config lives in a single JSON file per platform (see `docs/DESIGN.md`).
