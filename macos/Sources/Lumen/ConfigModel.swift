import Foundation
import Combine
import LumenCore

/// Observable wrapper around `LumenConfig` for the SwiftUI settings window.
/// Every change is persisted atomically to `config.json`; the daemon reads it
/// on its next poll.
final class ConfigModel: ObservableObject {

    private let paths = Paths.forCurrentUser()
    private var loading = false

    @Published var graceMinutes: Int = 10 { didSet { persist() } }
    @Published var pollSeconds: Int = 15 { didSet { persist() } }
    @Published var batteryFloorPercent: Int = 20 { didSet { persist() } }
    @Published var criticalBatteryPercent: Int = 10 { didSet { persist() } }
    @Published var maxHours: Int = 8 { didSet { persist() } }
    @Published var acOnly: Bool = false { didSet { persist() } }
    @Published var watchClaude: Bool = true { didSet { persist() } }
    @Published var watchCodex: Bool = true { didSet { persist() } }
    @Published var enableProcessTriggers: Bool = false { didSet { persist() } }
    @Published var cpuThresholdPercent: Int = 40 { didSet { persist() } }
    /// Edited as a comma/space-separated string; split on persist.
    @Published var processListText: String = "" { didSet { persist() } }
    @Published var mode: LumenMode = .auto { didSet { persist() } }
    @Published var language: String = "system" { didSet { persist() } }

    init() { reload() }

    func reload() {
        loading = true
        defer { loading = false }
        let c = ConfigStore.load(at: paths.configFile)
        graceMinutes = c.graceMinutes
        pollSeconds = c.pollSeconds
        batteryFloorPercent = c.batteryFloorPercent
        criticalBatteryPercent = c.criticalBatteryPercent
        maxHours = c.maxHours
        acOnly = c.acOnly
        watchClaude = c.watchClaude
        watchCodex = c.watchCodex
        enableProcessTriggers = c.enableProcessTriggers
        cpuThresholdPercent = c.cpuThresholdPercent
        processListText = c.processList.joined(separator: ", ")
        mode = c.mode
        language = c.language
    }

    private func persist() {
        guard !loading else { return }
        var c = ConfigStore.load(at: paths.configFile) // keep fields we don't own (timedUntil)
        c.graceMinutes = clamp(graceMinutes, 1, 120)
        c.pollSeconds = clamp(pollSeconds, 5, 300)
        c.batteryFloorPercent = clamp(batteryFloorPercent, 0, 100)
        c.criticalBatteryPercent = clamp(criticalBatteryPercent, 0, 100)
        c.maxHours = clamp(maxHours, 0, 48)
        c.acOnly = acOnly
        c.watchClaude = watchClaude
        c.watchCodex = watchCodex
        c.enableProcessTriggers = enableProcessTriggers
        c.cpuThresholdPercent = clamp(cpuThresholdPercent, 1, 100)
        c.processList = processListText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        c.mode = mode
        c.language = language
        ConfigStore.save(c, to: paths.configFile)
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}
