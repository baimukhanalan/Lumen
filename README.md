# Lumen

[![build](https://github.com/baimukhanalan/Lumen/actions/workflows/build.yml/badge.svg)](https://github.com/baimukhanalan/Lumen/actions/workflows/build.yml)

**Keep your laptop awake — with the lid closed — but only while your AI coding agents are actually working.**

Lumen is a small, premium menu-bar / tray utility for **macOS and Windows**. When Claude Code, Codex, Cursor, a local model, or a long build is running, Lumen prevents the machine from sleeping *even when the lid is shut*. The moment the work is done, it lets the machine sleep again to save battery.

> Status: 🚧 early development (private). Public release will ship signed installers for macOS and Windows.

---

## Why it exists

Most "keep awake" tools (`caffeinate`, IOKit power assertions, and the apps that wrap them) only stop the **idle** sleep timer. They do **not** override the separate **lid-close (clamshell)** sleep path. So the instant you shut the lid, your long-running agent task dies.

Lumen uses the real mechanism for clamshell:

- **macOS** — `pmset disablesleep` via a privileged helper.
- **Windows** — `SetThreadExecutionState` + lid-close power policy (`powercfg`).

And it ties that switch to **actual work**, not just "an app is open":

- Detects live **Claude Code** / **Codex** sessions by their session-log activity (survives long silent "thinking" pauses).
- Detects a configurable list of processes (Cursor, Ollama, Docker, `npm`/build tools…) with a CPU threshold.
- After a short grace window with no activity → normal sleep returns.

## Features

- 🖥 **Lid-closed keep-awake** tied to real agent/session activity.
- 🎛 **Premium UI** — native menu-bar (macOS) / system tray (Windows) with a live status icon and a full settings window.
- 🔋 **Safety governors** — battery floor + force-sleep on critical, thermal release, hard time cap, "AC only" mode.
- ⏱ **Timed sessions** — 15 min … 8 h, plus manual keep-awake / allow-sleep.
- 📱 **Remote-friendly** — a mode that keeps the machine reachable while you drive it from your phone (see docs for the physical limits of waking a *sleeping* machine).
- 🌍 **Localized** — English, Русский, Қазақша.
- 🌓 Light / dark.

## How it works

```
            ┌─────────────────────────┐
            │   Lumen UI (menu-bar)    │  status, settings, modes
            └─────────────┬───────────┘
                          │ IPC
            ┌─────────────▼───────────┐
            │  watcher / core logic    │  detects sessions, decides state,
            │  (session-activity)      │  applies safety governors
            └─────────────┬───────────┘
                          │ privileged call
            ┌─────────────▼───────────┐
   macOS →  │ pmset -a disablesleep    │
   Windows→ │ SetThreadExecutionState  │ + powercfg lid policy
            └──────────────────────────┘
```

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full architecture and [`shared/detection.md`](shared/detection.md) for the detection rules shared across platforms.

## Repository layout

```
macos/      SwiftUI/AppKit menu-bar app + privileged helper
windows/    .NET (C#) system-tray app + lid/power control
shared/     detection rules, config schema, localization strings
docs/        design & user documentation
.github/     CI: builds macOS (.app/.dmg) and Windows (.exe) artifacts
```

## Building

Nightly/CI builds are produced by GitHub Actions on every push (macOS + Windows runners). Local builds:

- **macOS:** `./macos/build.sh` → `macos/build/Lumen.app` (needs Xcode Command Line Tools; signing/notarization needs an Apple Developer ID).
- **Windows:** `dotnet publish windows/Lumen -c Release` (needs .NET SDK 8+).

## Roadmap

- [x] Proven core: session-activity detection + `pmset disablesleep` + safety governors (macOS prototype).
- [x] macOS premium app — menu-bar UI + SwiftUI settings + root daemon (builds via `swiftc`, no Xcode).
- [x] Windows app — .NET 8 tray + `SetThreadExecutionState` + `powercfg` lid policy + WPF settings.
- [x] CI builds both platforms on every push (macOS `.app` + Windows `.exe` artifacts).
- [ ] Installers + auto-update (Sparkle / winget) + code signing & notarization.
- [ ] Localization polish (en/ru/kk).

### Download

Until signed installers ship, grab the latest CI build from the **[Actions tab](https://github.com/baimukhanalan/Lumen/actions/workflows/build.yml)** → newest run → **Artifacts** (`Lumen-macos`, `Lumen-windows`). These are unsigned, so macOS needs right-click → Open once, and Windows may show a SmartScreen "Run anyway".

## License

[MIT](LICENSE)
