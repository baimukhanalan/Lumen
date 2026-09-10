# Lumen — macOS

A premium menu-bar app that keeps your Mac awake **only while real agent work
is happening** (Claude Code / Codex sessions), and safely lets it sleep
otherwise. Behavior matches the proven prototype in [`../prototype`](../prototype)
and the cross-platform rules in [`../shared/detection.md`](../shared/detection.md).

Two products ship together:

| Product | What it is | Runs as |
|---|---|---|
| `Lumen.app` | AppKit menu-bar controller + SwiftUI settings | the user (no root) |
| `lumen-daemon` | compiled Swift watcher implementing the decision loop | **root**, via a LaunchDaemon |

The daemon owns the privileged `pmset -a disablesleep 0/1` calls. The UI only
edits the shared config and flag files — it never needs root at runtime.

---

## Build

Everything builds with the **Command Line Tools** `swiftc` — no full Xcode, no
`xcodebuild`, no `.xcodeproj`.

```sh
./macos/build.sh
```

This produces:

```
macos/build/Lumen.app
macos/build/Lumen.app/Contents/MacOS/Lumen              # menu-bar app
macos/build/Lumen.app/Contents/Resources/lumen-daemon   # root watcher (bundled)
macos/build/Lumen.app/Contents/Resources/i18n/*.json    # localization
```

The script is idempotent (it recreates `build/` each run) and prints the final
app path. It compiles a shared static library `LumenCore`, links the two
executables against it, hand-assembles the `.app`, and ad-hoc code-signs it so
it runs locally.

**Verified build command:** `./macos/build.sh` (Swift 6.4 compiler, CLT SDK,
targeting `<arch>-apple-macos12.0`).

A `Package.swift` is also provided for editor/IDE tooling and `swift build`
(same sources, Swift 5 language mode). `swift build` produces the two
executables but does **not** assemble the `.app` — use `build.sh` for that.

---

## Run & install

1. `open macos/build/Lumen.app` — a menu-bar icon appears (no Dock icon,
   `LSUIElement`).
2. On first run Lumen offers to install the background daemon. Accepting shows
   **one** native macOS administrator prompt (you type your own password —
   Lumen never sees it). This:
   - copies `lumen-daemon` → `/usr/local/libexec/lumen-daemon`
   - writes `/Library/LaunchDaemons/com.lumen.daemon.plist`
     (with your home baked into `LUMEN_USER_HOME`)
   - `launchctl bootstrap`s it (RunAtLoad + KeepAlive)
3. After that, everything is password-free: mode changes and timed sessions
   just edit the config / flag files that the daemon reads each poll.

Reinstall/update or remove the daemon anytime from **Settings › About**.

### Menu-bar states (SF Symbols)

| Icon | Meaning |
|---|---|
| `bolt.fill` | Awake — sleep disabled (agent working / manual keep-awake) |
| `eye` | Armed — daemon running, watching, sleep currently allowed |
| `moon.zzz.fill` | Paused — Allow-sleep mode |
| `exclamationmark.triangle` | Daemon not installed / not reporting |

### Modes

- **Auto** — keep-awake follows detected session/process activity.
- **Keep awake** — manual hold (still subject to safety governors).
- **Allow sleep** — manual release; overrides everything.
- **Remote** — like Keep awake, plus wake-on-network on AC (the daemon toggles
  `pmset -c womp`).
- **Timed session** — keep awake for 15m–8h, then fall back to Auto.

---

## Configuration

Single JSON file, shared with the daemon, schema per `shared/detection.md`:

```
~/Library/Application Support/Lumen/config.json
```

Defaults (match the prototype): `graceMinutes 10`, `pollSeconds 15`,
`batteryFloorPercent 20`, `criticalBatteryPercent 10`, `maxHours 8`,
`cpuThresholdPercent 40`, `watchClaude/watchCodex true`, process triggers off.

Manual-override flag files (also written by the UI, compatible with the shell
CLI) live alongside it: `force-on`, `force-off`.

The daemon publishes live status to `/var/run/lumen-state.json`, which the UI
polls to render the icon and status line.

### Safety governors (implemented exactly per spec, verified by unit tests)

Applied in order, each can only **allow** sleep:
critical battery (≤10%) → battery floor (≤20%) → AC-only → thermal
(Serious/Critical via `ProcessInfo.thermalState`) → hard cap (≥8h continuous,
with a `capped` latch cleared only by a genuine idle period).

Crash/reboot safe: the daemon restores `disablesleep 0` on graceful termination
(SIGTERM/SIGINT) and re-evaluates immediately on relaunch, so a stuck override
can never brick sleep. `KeepAlive` relaunches it if it dies.

---

## Localization

Strings load from `shared/i18n/{en,ru,kk}.json` (bundled into the app's
`Contents/Resources/i18n`). Default follows the system language and falls back
to English; a specific language can be pinned in Settings › General.

---

## Privilege model & what still needs signing

The privileged install uses AppleScript `do shell script … with administrator
privileges` (native auth dialog). This is the **shippable-now** path from
`docs/DESIGN.md`. The code is isolated in `PrivilegedInstaller` so it can be
swapped for `SMAppService` + XPC once a Developer ID is available, without
touching callers.

Requires a signing identity / Apple Developer Program (not possible in a
CLT-only build):

- **Developer ID signature + notarization** of `Lumen.app` and the daemon
  (the build currently ad-hoc signs, which is fine locally but Gatekeeper will
  warn on other machines).
- **`SMAppService`-registered helper** (the "Premium" target) to replace the
  AppleScript installer with a single signed, XPC-driven helper.
- **Sparkle auto-update** and a signed/notarized `.dmg` / Homebrew cask for
  distribution.

Everything else — detection, all safety governors, the daemon loop, the
menu-bar UI, the SwiftUI settings, localization, and the one-time installer —
compiles and runs today with the Command Line Tools only.
