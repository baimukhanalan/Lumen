import Foundation

/// Thin, testable wrappers over the macOS facilities the daemon needs:
/// power state (`pmset`), thermal pressure (`ProcessInfo`), and filesystem
/// scans for session-log and process activity.
public struct SystemProbe: Sendable {

    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }

    // MARK: - Power (pmset)

    public struct PowerState: Sendable {
        public var onBattery: Bool
        public var percent: Int?
    }

    /// Parses `pmset -g batt`. Desktops report "AC Power" with no percentage.
    public func powerState() -> PowerState {
        let out = Shell.run("/usr/bin/pmset", ["-g", "batt"]).stdout
        let onBattery = out.contains("Battery Power")
        var percent: Int?
        // First "<n>%" token on the first battery line.
        if let range = out.range(of: #"[0-9]+%"#, options: .regularExpression) {
            let token = out[range].dropLast() // strip '%'
            percent = Int(token)
        }
        return PowerState(onBattery: onBattery, percent: percent)
    }

    /// True if the OS reports elevated thermal pressure (Serious/Critical).
    public func thermalSerious() -> Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return true
        default: return false
        }
    }

    public func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Reads the current `disablesleep` value reported by `pmset -g`.
    public func sleepDisabled() -> Bool {
        let out = Shell.run("/usr/bin/pmset", ["-g"]).stdout
        for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
            // Format: " SleepDisabled        1"
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let last = parts.last { return last == "1" }
        }
        return false
    }

    /// Applies `pmset -a disablesleep 0/1`. Requires root. Returns success.
    @discardableResult
    public func setDisableSleep(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/pmset", ["-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    /// Toggles wake-on-network on AC (`pmset -c womp 0/1`). Requires root.
    @discardableResult
    public func setWakeOnNetwork(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/pmset", ["-c", "womp", on ? "1" : "0"]).status == 0
    }

    // MARK: - Session-log activity

    /// True if any watched `*.jsonl` was modified within `graceMinutes`.
    public func sessionActive(config: LumenConfig, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(config.graceMinutes) * 60.0)
        var dirs: [String] = []
        if config.watchClaude { dirs.append(paths.claudeProjectsDir) }
        if config.watchCodex { dirs.append(paths.codexSessionsDir) }
        for dir in dirs where anyJSONLModified(inDirectory: dir, since: cutoff) {
            return true
        }
        return false
    }

    private func anyJSONLModified(inDirectory dir: String, since cutoff: Date) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let url = URL(fileURLWithPath: dir)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return false }

        for case let fileURL as URL in en {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { continue }
            if mtime >= cutoff { return true }
        }
        return false
    }

    // MARK: - Process + CPU triggers

    /// True if any process whose executable basename is in `processList` is
    /// sustaining CPU at or above `cpuThresholdPercent`.
    public func processActive(config: LumenConfig) -> Bool {
        guard config.enableProcessTriggers, !config.processList.isEmpty else {
            return false
        }
        let wanted = Set(config.processList.map { ($0 as NSString).lastPathComponent })
        let out = Shell.run("/bin/ps", ["-axo", "comm=,%cpu="]).stdout
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sep = trimmed.range(of: " ", options: .backwards) else { continue }
            let comm = String(trimmed[..<sep.lowerBound])
            let cpuStr = trimmed[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            let base = (comm as NSString).lastPathComponent
            guard wanted.contains(base), let cpu = Double(cpuStr) else { continue }
            if cpu >= Double(config.cpuThresholdPercent) { return true }
        }
        return false
    }
}
