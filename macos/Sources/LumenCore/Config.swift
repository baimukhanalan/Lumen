import Foundation

/// User-facing operating mode. Stored in `config.json` and mirrored by the
/// UI onto the flag files for compatibility with the shell CLI.
public enum LumenMode: String, Codable, CaseIterable, Sendable {
    case auto    // keep-awake follows detected session/process activity
    case on      // manual keep-awake (still subject to safety governors)
    case off     // manual allow-sleep (overrides everything)
    case remote  // like `on`, plus wake-on-network on AC (womp)
}

/// The shared configuration, one JSON file per platform, schema per
/// `shared/detection.md`. All keys are optional on disk: decoding falls back
/// to the documented defaults so a partial or older file still loads cleanly.
public struct LumenConfig: Codable, Equatable, Sendable {

    // Detection / timing
    public var graceMinutes: Int
    public var pollSeconds: Int

    // Safety governors
    public var batteryFloorPercent: Int
    public var criticalBatteryPercent: Int
    public var maxHours: Int
    public var acOnly: Bool

    // Session-log triggers
    public var watchClaude: Bool
    public var watchCodex: Bool

    // Process + CPU triggers
    public var enableProcessTriggers: Bool
    public var processList: [String]
    public var cpuThresholdPercent: Int

    // Lumen UI extensions (not part of the cross-platform detection core, but
    // stored in the same file so both the UI and daemon agree).
    public var mode: LumenMode
    public var timedUntil: Double   // epoch seconds; 0 = no timed session
    public var language: String     // "system" | "en" | "ru" | "kk"

    /// Documented defaults from `shared/detection.md`.
    public static let defaults = LumenConfig(
        graceMinutes: 10,
        pollSeconds: 15,
        batteryFloorPercent: 20,
        criticalBatteryPercent: 10,
        maxHours: 8,
        acOnly: false,
        watchClaude: true,
        watchCodex: true,
        enableProcessTriggers: false,
        processList: [],
        cpuThresholdPercent: 40,
        mode: .auto,
        timedUntil: 0,
        language: "system"
    )

    public init(
        graceMinutes: Int,
        pollSeconds: Int,
        batteryFloorPercent: Int,
        criticalBatteryPercent: Int,
        maxHours: Int,
        acOnly: Bool,
        watchClaude: Bool,
        watchCodex: Bool,
        enableProcessTriggers: Bool,
        processList: [String],
        cpuThresholdPercent: Int,
        mode: LumenMode,
        timedUntil: Double,
        language: String
    ) {
        self.graceMinutes = graceMinutes
        self.pollSeconds = pollSeconds
        self.batteryFloorPercent = batteryFloorPercent
        self.criticalBatteryPercent = criticalBatteryPercent
        self.maxHours = maxHours
        self.acOnly = acOnly
        self.watchClaude = watchClaude
        self.watchCodex = watchCodex
        self.enableProcessTriggers = enableProcessTriggers
        self.processList = processList
        self.cpuThresholdPercent = cpuThresholdPercent
        self.mode = mode
        self.timedUntil = timedUntil
        self.language = language
    }

    // Tolerant decoding: any missing key uses its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LumenConfig.defaults
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // `try?` flattens the double optional: nil on a missing key or a
            // decode error, the value otherwise.
            if let decoded = try? c.decodeIfPresent(T.self, forKey: key) {
                return decoded
            }
            return fallback
        }
        graceMinutes = v(.graceMinutes, d.graceMinutes)
        pollSeconds = v(.pollSeconds, d.pollSeconds)
        batteryFloorPercent = v(.batteryFloorPercent, d.batteryFloorPercent)
        criticalBatteryPercent = v(.criticalBatteryPercent, d.criticalBatteryPercent)
        maxHours = v(.maxHours, d.maxHours)
        acOnly = v(.acOnly, d.acOnly)
        watchClaude = v(.watchClaude, d.watchClaude)
        watchCodex = v(.watchCodex, d.watchCodex)
        enableProcessTriggers = v(.enableProcessTriggers, d.enableProcessTriggers)
        processList = v(.processList, d.processList)
        cpuThresholdPercent = v(.cpuThresholdPercent, d.cpuThresholdPercent)
        mode = v(.mode, d.mode)
        timedUntil = v(.timedUntil, d.timedUntil)
        language = v(.language, d.language)
    }
}

/// Thread-safe-enough load/save helpers. Writes are atomic; the parent
/// directory is created on demand.
public enum ConfigStore {

    public static func load(at path: String) -> LumenConfig {
        guard let data = FileManager.default.contents(atPath: path) else {
            return .defaults
        }
        do {
            return try JSONDecoder().decode(LumenConfig.self, from: data)
        } catch {
            // Corrupt config should never brick the app; fall back to defaults.
            return .defaults
        }
    }

    @discardableResult
    public static func save(_ config: LumenConfig, to path: String) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Ensure a config file exists on disk, writing defaults if it doesn't.
    public static func ensureExists(at path: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        save(.defaults, to: path)
    }
}
