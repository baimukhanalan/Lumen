# Lumen — product strategy & v2 roadmap

*Synthesized from a competitive sweep and a pain-point sweep (Reddit, Hacker News, GitHub issues) across Claude Code, Codex, Cursor, Aider, and Ollama users.*

## Positioning

**Lumen is the keep-awake built for AI coding agents.** It knows when Claude Code, Codex, or Cursor is actually working, keeps the machine running with the lid shut *only while the run needs it*, then lets it sleep. A battery-and-thermal governor makes overnight runs safe; notifications tell you the moment the agent finishes or stalls waiting for you.

> Not a dumb toggle, not a mouse jiggler, not a `sudo` hack off GitHub — the trusted, signed, cross-platform way to let your agent work while you're away.

**The wedge nobody occupies:** agent-native intelligence × trustworthy lid-closed running × cross-platform × remote observability.

## The core technical truth

`caffeinate` and IOKit power assertions only block **idle** sleep. Closing the lid is a separate, lower-level sleep request no assertion overrides. The only software lever that beats it (battery, no external display) is `pmset -a disablesleep 1` — which needs a privileged helper (off-limits to sandboxed MAS apps) and, left raw, burns battery/heat under a closed lid. Lumen's value = that lever, tied to **real session activity** + a **safety governor**.

## Competitive landscape

| Tool | Lid-closed | Agent-aware | Safety | Phone push | Cross-platform | Trusted | Price |
|---|---|---|---|---|---|---|---|
| **Lumen** | ✅ | ✅ session logs | ✅ battery+thermal | roadmap | ✅ mac+win | in progress | freemium |
| LidRun | ✅ | ✅ process list | ✅ | — | mac | ✅ | $9 one-time |
| LidSleepToggle | ✅ | ✅ Claude logs | ✅ | — | mac 13+ | ad-hoc | free/OSS |
| VibeMenu | assertion | ✅ Claude/Codex | thermal read | — | mac | ad-hoc | free/OSS |
| Amphetamine | v5, quirky | app/CPU | battery | — | mac | MAS sandbox | free |
| caffeinate | — | wrap only | — | — | mac | built-in | free |
| PowerToys Awake | — | — | — | — | win | ✅ | free |

The lid-closed lever is currently wielded almost only by free ad-hoc-signed GitHub projects and one $9 indie app (LidRun). **Nobody ships trusted + agent-native + cross-platform + remote.** The niche is being defined this year — Lumen can be the category-defining product first.

## Top validated pains (beyond "the machine sleeps")

1. **"Did it finish or is it stuck?"** — agents stall for hours on approval prompts / hang on a spinner (Cursor forum #148230, openai/codex #4491).
2. **No phone ping** — want a notification on completion / error / needs-input for *any* agent; Anthropic Remote Control is Claude-only + subscription.
3. **Battery & thermal** — Claude Code can drain a full battery in ~2h and thermal-throttle; dangerous lid-shut in a bag (claude-code #17563, #8302).
4. **Silent overnight death** — OOM (exit 137), tool loops, context-bloat backoff, zombies; never hit a log. Least-served pain.
5. **Juggling 3–5 sessions** — which one needs me now (claude-code-monitor, Chive, Tactic Remote).
6. **Quota hit mid-run** — two overlapping clocks; want at-a-glance "≈30 min left" (SessionWatcher).

## v2 roadmap

Almost all of this builds on the **same session logs Lumen already reads** — most fit the existing menu-bar app, no backend.

### Tier 1 — quick wins (ship first, weeks)
- Desktop notifications on state change (done / waiting-on-approval / error)
- Idle & stuck detector ("no activity > N min")
- Keep-awake presets (auto · until-done+N · battery-safe · hard-on)
- Battery & thermal guardian with rules
- Generic outbound webhooks

### Tier 2 — differentiators (the moat, 1–2 months)
- Multi-agent live dashboard + jump-to-session
- Phone push for every agent (Telegram / ntfy / Slack relay)
- Local rules/automation engine ("when X finishes → notify + sleep")
- Silent-failure watchdog (OOM / loop / zombie / context-bloat)
- Run history & stats (duration, exit, peak temp, battery delta, tokens)

### Tier 3 — moonshots (AI / bot delight)
- Two-way phone control (approve / steer from lock screen)
- AI end-of-run summary pushed to phone (local Ollama)
- AI triage bot (auto-approve safe steps, escalate the rest)
- Scheduled wake-to-run (wake at 2am → run → sleep)

## Pricing

Subscriptions are resented in this category. Monetize the cloud layer, keep the core one-time.

- **Free:** open-lid keep-awake + basic agent detection + menu-bar status (competes the OSS crowd out).
- **Pro, one-time ($19–29):** lid-closed + safety governor + presets + history + finish-then-sleep + scheduled wake.
- **Cloud/Team (modest sub):** phone push, remote control, blocked-on-approval alerts, fleet policies/MDM.

## Pains to avoid (category complaints)
Lid-closed must *just work*; ship a governor + display-blank so unattended runs are safe; default-correct and glanceable (Amphetamine's triggers confuse); never inject fake input (jigglers break consoles); notarize + clean privileged helper (trust); solve Windows Modern Standby + lock-screen; always show *why* it's awake and when it stopped.

*Full visual brief: published as a Lumen Product Brief artifact.*
