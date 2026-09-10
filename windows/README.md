# Lumen for Windows

A system-tray app (.NET 8, C#) that keeps Windows awake — **with the lid
closed** — but only while your AI coding agents are actually working. When the
work stops, it lets the machine sleep again. Behaviour matches the macOS app;
the shared decision logic lives in [`../shared/detection.md`](../shared/detection.md).

## What it does

- **Tray presence** — a `NotifyIcon` whose graphic reflects state (awake / armed
  / paused) with a context menu: a live status line, mode items
  (Auto / Keep awake / Allow sleep / Remote), a **Timed session** submenu
  (15 m … 8 h), **Settings…**, and **Exit**. Double-click opens Settings.
- **Keep-awake** via `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED
  | ES_AWAYMODE_REQUIRED)`, cleared with `ES_CONTINUOUS` alone. Away-mode keeps
  work running with the lid shut / display off.
- **Detection** (every `pollSeconds`, default 15):
  - Session-log activity: `%USERPROFILE%\.claude\projects\**\*.jsonl` and
    `%USERPROFILE%\.codex\sessions\**\*.jsonl` modified within `graceMinutes`.
  - Optional process + CPU triggers (`processList`, `cpuThresholdPercent`),
    CPU computed from `Process.TotalProcessorTime` deltas.
  - Manual overrides (Auto / Keep awake / Allow sleep / Remote), persisted.
- **Safety governors** (in order): critical battery (≤ 10 %) force sleep,
  battery floor (≤ 20 %), AC-only, thermal (best-effort WMI, degrades quietly),
  and a hard cap on continuous awake time (default 8 h) with a persisted
  `onSince` / `capped` latch.
- **Crash/exit safety** — the execution-state assertion is cleared by the OS on
  process exit, and any lid-policy change is restored on exit (and on next
  startup if a crash left it changed).

## Configuration

A single JSON file, shared-schema with macOS:

```
%APPDATA%\Lumen\config.json
```

Runtime state (mode, `onSince`, cap latch, lid bookkeeping) is kept separately
in `%APPDATA%\Lumen\state.json` so settings never churn. The Settings window
(General / Triggers / Safety / About) reads and writes `config.json`; the watcher
re-reads it every poll, so external edits take effect too. Light/dark follows the
system "apps" theme where feasible.

Keys and defaults are documented in
[`../shared/detection.md`](../shared/detection.md). Windows adds two keys:

| key | default | meaning |
|---|---|---|
| `manageLidPolicy` | `false` | manage the lid-close power policy while active |
| `language` | `null` | UI language (`en` / `ru` / `kk`); null follows the OS |

## Localization

Strings live in `i18n/{en,ru,kk}.json` (copied next to the executable). English
is the base; the selected language overlays it, so any missing key falls back to
English. Default follows the OS UI culture.

## Lid-close policy (premium extra)

Windows' *"when I close the lid"* is a separate power-policy setting, so
`SetThreadExecutionState` alone will not stop a lid-close sleep on every machine.
Enable **Settings → General → "Manage lid-close policy while active"** and Lumen
will, while keep-awake is on:

1. read and store the current AC/DC lid-action indices (non-elevated
   `powercfg /query`),
2. set the lid-close action to **Do nothing** for AC and DC and re-activate the
   scheme (`powercfg /setacvalueindex … SUB_BUTTONS LIDACTION 0`, the `-setdc…`
   variant, then `-setactive SCHEME_CURRENT`),
3. restore the stored values when keep-awake turns off or the app exits.

The set/restore commands run through a single elevated `cmd.exe` launched with
`Verb = "runas"`, so there is **exactly one UAC prompt** per enable and per
restore. The app itself runs **non-elevated** (`asInvoker` in the manifest). If
you dismiss the UAC prompt, Lumen falls back to keep-awake via away-mode only and
shows a notification — it does not keep re-prompting during that awake period.

## Build

Requires the .NET 8 SDK on Windows.

```powershell
dotnet publish windows/Lumen/Lumen.csproj -c Release -r win-x64 --self-contained false
```

This is framework-dependent: the target machine needs the
**.NET 8 Desktop Runtime**. CI (`.github/workflows/build.yml`, `windows-latest`)
publishes to `dist/windows` and uploads it as the `Lumen-windows` artifact.

For a self-contained build (no runtime prerequisite, larger output):

```powershell
dotnet publish windows/Lumen/Lumen.csproj -c Release -r win-x64 --self-contained true
```

## Run

Launch `Lumen.exe`. There is no taskbar window — look for the tray icon (it may
be under the "^" overflow). Right-click for the menu; double-click for Settings.

## Packaging (later step)

Distribution via **Inno Setup** or **MSIX** plus a **winget** manifest is a
follow-up. Add a startup shortcut / registry `Run` entry for launch-at-login.
Code-signing (see below) should be wired before public distribution.

## Notes on dependencies

- Only one NuGet package is used: `System.Management` (pinned `8.0.0`,
  Microsoft-owned) for the best-effort WMI thermal read. Everything else is BCL
  + P/Invoke.
- Battery / AC state comes from `SystemInformation.PowerStatus` (no WMI needed).
- Tray icons are generated in code (`IconFactory`), so the repo ships no binary
  image assets.

## Code signing

Nothing here is signed. Once a code-signing certificate is available:

- Sign `Lumen.exe` (and any installer) with `signtool` so SmartScreen /
  "Unknown publisher" warnings go away.
- Without a signature, the one-time UAC prompt for the lid-policy step shows an
  "unknown publisher" dialog; signing makes it show the verified publisher.
- The winget / MSIX packaging step should consume the signed binaries.
