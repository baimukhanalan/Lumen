import Foundation
import LumenCore

/// Applies user control actions by editing `config.json` and keeping the
/// compatibility flag files in sync. Runs entirely as the user — no root
/// needed; the daemon observes the changes on its next poll.
enum ControlWriter {

    private static let paths = Paths.forCurrentUser()

    /// Timed-session presets shown in the menu, in seconds.
    static let timedPresets: [(labelKey: String, seconds: Double)] = [
        ("timed.15m", 15 * 60),
        ("timed.30m", 30 * 60),
        ("timed.1h", 60 * 60),
        ("timed.2h", 2 * 60 * 60),
        ("timed.4h", 4 * 60 * 60),
        ("timed.8h", 8 * 60 * 60),
    ]

    static func currentConfig() -> LumenConfig {
        ConfigStore.load(at: paths.configFile)
    }

    static func setMode(_ mode: LumenMode) {
        var cfg = currentConfig()
        cfg.mode = mode
        if mode != .auto {
            // Explicit modes clear any pending timed session.
            cfg.timedUntil = 0
        }
        ConfigStore.save(cfg, to: paths.configFile)
        syncFlags(for: cfg)
    }

    /// Keep awake for `seconds` from now, then fall back to Auto.
    static func startTimedSession(seconds: Double) {
        var cfg = currentConfig()
        cfg.mode = .auto
        cfg.timedUntil = Date().timeIntervalSince1970 + seconds
        ConfigStore.save(cfg, to: paths.configFile)
        syncFlags(for: cfg)
    }

    static func stopTimedSession() {
        var cfg = currentConfig()
        cfg.timedUntil = 0
        ConfigStore.save(cfg, to: paths.configFile)
        syncFlags(for: cfg)
    }

    /// Mirror the effective override onto the flag files, so the shell CLI and
    /// the daemon agree even if only one channel is used.
    private static func syncFlags(for cfg: LumenConfig) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: paths.supportDir, withIntermediateDirectories: true)
        let nowEpoch = Date().timeIntervalSince1970
        let timedActive = cfg.timedUntil > nowEpoch
        let wantOn = (cfg.mode == .on || cfg.mode == .remote) || timedActive
        let wantOff = (cfg.mode == .off)

        setFlag(paths.forceOnFlag, present: wantOn)
        setFlag(paths.forceOffFlag, present: wantOff)
    }

    private static func setFlag(_ path: String, present: Bool) {
        let fm = FileManager.default
        if present {
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: Data())
            }
        } else {
            try? fm.removeItem(atPath: path)
        }
    }
}
