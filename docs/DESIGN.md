# Lumen — architecture & design

This document is the source of truth for how Lumen is built on each platform. Detection rules live in [`../shared/detection.md`](../shared/detection.md).

## Product principles

1. **Real work, not open apps.** Keep-awake follows agent/session activity.
2. **Safe by default.** Never brick sleep: battery/thermal/time governors + crash/reboot self-heal.
3. **Premium & quiet.** A single menu-bar/tray icon that shows state at a glance; a settings window for everything else. No dock icon, no window clutter.
4. **Identical behavior cross-platform.** Same decision logic, same defaults; only the OS glue differs.

## Shared config

One JSON file, same schema on both platforms:

- macOS: `~/Library/Application Support/Lumen/config.json`
- Windows: `%APPDATA%\Lumen\config.json`

Keys per `shared/detection.md`. The UI reads/writes this file; the core watcher reads it each poll.

## macOS

**App:** menu-bar app (LSUIElement, no dock icon). AppKit `NSStatusItem` for the icon/menu; settings window in SwiftUI hosted via `NSHostingController` (builds with Swift 6 + Command Line Tools; no full Xcode required for CI artifact).

**Privilege model:** `pmset -a disablesleep 0/1` needs root. Two supported paths:

- **Preferred (prototype, shippable now):** a root `LaunchDaemon` running the watcher, which owns the pmset calls. The UI only writes control flags + config; it never needs root at runtime.
- **Premium (target):** a privileged helper installed via `SMAppService` (like the original Awayke) and driven over XPC, so the whole thing is one signed app with a one-time approval.

**Thermal:** read thermal pressure via `powermetrics`/`ProcessInfo.thermalState`.

**Icon states:** asleep (allowed) · armed (watching, currently allowed) · awake (sleep disabled) · paused (manual off).

**Distribution:** signed + notarized `.dmg`; Homebrew cask; Sparkle auto-update. CI produces an unsigned `.app`/zip until signing secrets are added.

The proven prototype (bash watcher + LaunchDaemon + control CLI) lives in [`../prototype/`](../prototype/) and is the behavioral reference the native app must match.

## Windows

**App:** system-tray app (.NET 8, WPF for settings + `NotifyIcon` for tray). No taskbar window; settings window on demand.

**Keep-awake:** `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED)` to hold the system awake; clear with `ES_CONTINUOUS` alone. Away-mode keeps work running with the display off.

**Lid-close:** Windows' "when I close the lid" is a power-policy setting. Lumen offers to set *Do nothing* (on AC and/or battery) via `powercfg -setacvalueindex/-setdcvalueindex … SUB_BUTTONS LIDACTION 0` while active, and restores the previous value when it stops. This requires elevation (UAC); done via a manifest requesting `requireAdministrator` for the policy step only, or a scheduled task.

**Battery/thermal:** WMI (`Win32_Battery`, `MSAcpi_ThermalZoneTemperature`) / `SystemInformation.PowerStatus`.

**Icon states:** mirror macOS.

**Distribution:** Inno Setup or MSIX installer; `winget` manifest. Optional code-signing cert.

## CI

`.github/workflows/build.yml`:

- `macos` job on `macos-14`: runs `macos/build.sh`, uploads `Lumen.app` zip.
- `windows` job on `windows-latest`: `dotnet publish`, uploads the exe.
- On tags `v*`: attach artifacts to a GitHub Release.

Signing is wired to repository secrets (`APPLE_*`, `WINDOWS_CERT_*`) and is skipped gracefully when they are absent (unsigned artifacts).

## Localization

Strings in `shared/i18n/{en,ru,kk}.json`; each app loads the matching bundle. Default follows the OS language, falling back to English.
