import Foundation

/// The live state the daemon publishes to `/var/run/lumen-state.json`.
///
/// It doubles as the daemon's persistence: `onSince` and `capped` are read
/// back on the next poll (and after a relaunch) so the hard-cap latch and the
/// continuous-awake timer survive restarts.
public struct DaemonState: Codable, Equatable, Sendable {

    /// The decision from `DecisionEngine` for the most recent poll.
    public var shouldStayAwake: Bool
    /// What `pmset` reports right now (`disablesleep`), i.e. the applied state.
    public var sleepDisabled: Bool
    /// Human-readable English one-liner explaining the current decision.
    /// Kept for the daemon log and as the UI's fallback if `reasonKey` is
    /// missing or unknown.
    public var reason: String
    /// Stable machine key the UI localizes (e.g. "reason.activeSession").
    /// Optional for backward tolerance with state files from older daemons.
    public var reasonKey: String?
    /// Numeric args to interpolate into the localized `reasonKey`, in order.
    /// Optional for backward tolerance with older state files.
    public var reasonValues: [Int]?
    public var mode: LumenMode

    // Inputs, surfaced for the UI's status detail.
    public var sessionActive: Bool
    public var processActive: Bool
    public var onBattery: Bool
    public var batteryPercent: Int?
    public var thermal: String        // nominal | fair | serious | critical
    public var timedUntil: Double

    // Persisted state-machine fields.
    public var onSince: Double         // epoch seconds; 0 = not currently awake
    public var capped: Bool            // hard-cap latch

    // Metadata.
    public var updatedAt: Double
    public var daemonVersion: String

    public static let empty = DaemonState(
        shouldStayAwake: false,
        sleepDisabled: false,
        reason: "starting up",
        reasonKey: "reason.starting",
        reasonValues: [],
        mode: .auto,
        sessionActive: false,
        processActive: false,
        onBattery: false,
        batteryPercent: nil,
        thermal: "nominal",
        timedUntil: 0,
        onSince: 0,
        capped: false,
        updatedAt: 0,
        daemonVersion: LumenVersion.string
    )

    public init(
        shouldStayAwake: Bool,
        sleepDisabled: Bool,
        reason: String,
        reasonKey: String? = nil,
        reasonValues: [Int]? = nil,
        mode: LumenMode,
        sessionActive: Bool,
        processActive: Bool,
        onBattery: Bool,
        batteryPercent: Int?,
        thermal: String,
        timedUntil: Double,
        onSince: Double,
        capped: Bool,
        updatedAt: Double,
        daemonVersion: String
    ) {
        self.shouldStayAwake = shouldStayAwake
        self.sleepDisabled = sleepDisabled
        self.reason = reason
        self.reasonKey = reasonKey
        self.reasonValues = reasonValues
        self.mode = mode
        self.sessionActive = sessionActive
        self.processActive = processActive
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.timedUntil = timedUntil
        self.onSince = onSince
        self.capped = capped
        self.updatedAt = updatedAt
        self.daemonVersion = daemonVersion
    }
}

public enum StateStore {

    public static func load(at path: String) -> DaemonState? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(DaemonState.self, from: data)
    }

    @discardableResult
    public static func save(_ state: DaemonState, to path: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return false }
        // Written by root; make it world-readable so the UI can poll it.
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            chmod(path, 0o644)
            return true
        } catch {
            return false
        }
    }
}

public enum LumenVersion {
    public static let string = "1.0.0"
}
