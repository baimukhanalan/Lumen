import Foundation

/// Everything the decision needs, gathered by the platform layer so the engine
/// itself is pure and unit-testable.
public struct DecisionInputs: Sendable {
    public var forceOn: Bool
    public var forceOff: Bool
    public var sessionActive: Bool
    public var processActive: Bool

    public var onBattery: Bool
    public var batteryPercent: Int?     // nil if unknown / desktop
    public var thermalSerious: Bool     // ProcessInfo thermalState >= .serious

    // Governor knobs (from config).
    public var criticalBatteryPercent: Int
    public var batteryFloorPercent: Int
    public var acOnly: Bool
    public var maxHours: Int             // 0 = no hard cap

    public var now: Double

    // Persisted latch state carried between polls.
    public var onSince: Double
    public var capped: Bool

    public init(
        forceOn: Bool,
        forceOff: Bool,
        sessionActive: Bool,
        processActive: Bool,
        onBattery: Bool,
        batteryPercent: Int?,
        thermalSerious: Bool,
        criticalBatteryPercent: Int,
        batteryFloorPercent: Int,
        acOnly: Bool,
        maxHours: Int,
        now: Double,
        onSince: Double,
        capped: Bool
    ) {
        self.forceOn = forceOn
        self.forceOff = forceOff
        self.sessionActive = sessionActive
        self.processActive = processActive
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.thermalSerious = thermalSerious
        self.criticalBatteryPercent = criticalBatteryPercent
        self.batteryFloorPercent = batteryFloorPercent
        self.acOnly = acOnly
        self.maxHours = maxHours
        self.now = now
        self.onSince = onSince
        self.capped = capped
    }
}

public struct Decision: Equatable, Sendable {
    public var shouldStayAwake: Bool
    /// Human-readable English one-liner (used verbatim in the daemon log).
    public var reason: String
    /// Stable machine key the UI localizes (e.g. "reason.activeSession").
    public var reasonKey: String
    /// Numeric args to interpolate into the localized `reasonKey`, in order
    /// (e.g. battery percent then threshold, or the hard-cap hours).
    public var reasonValues: [Int]
    /// Updated latch state to persist for the next poll.
    public var onSince: Double
    public var capped: Bool

    public init(shouldStayAwake: Bool,
                reason: String,
                reasonKey: String = "",
                reasonValues: [Int] = [],
                onSince: Double,
                capped: Bool) {
        self.shouldStayAwake = shouldStayAwake
        self.reason = reason
        self.reasonKey = reasonKey
        self.reasonValues = reasonValues
        self.onSince = onSince
        self.capped = capped
    }
}

/// The cross-platform decision, implemented precisely per `shared/detection.md`
/// and matching the proven `prototype/lumen-watch.sh` behavior.
public enum DecisionEngine {

    public static func evaluate(_ i: DecisionInputs) -> Decision {
        // 1) Manual override has highest priority. `forceOff` beats everything.
        //    An "active" signal is a keep-awake request that is NOT vetoed by a
        //    manual allow-sleep.
        let requested = i.forceOn || i.sessionActive || i.processActive
        let active = requested && !i.forceOff

        var onSince = i.onSince
        var capped = i.capped
        var want: Bool
        var reason: String
        var reasonKey: String
        var reasonValues: [Int] = []

        if !active {
            // Idle (or manual allow-sleep) → full self-heal reset. This is the
            // "genuine idle period" that clears the hard-cap latch.
            want = false
            onSince = 0
            capped = false
            if i.forceOff {
                reason = "manual: allow sleep"
                reasonKey = "reason.manualOff"
            } else {
                reason = "idle — no active session"
                reasonKey = "reason.idle"
            }
        } else if capped {
            // Hard cap already latched: stay asleep until an idle period clears
            // it (handled by the branch above on a future poll).
            want = false
            reason = "hard cap reached — waiting for idle to re-arm"
            reasonKey = "reason.hardCapWaiting"
        } else {
            want = true
            if onSince == 0 { onSince = i.now }
            if i.maxHours > 0 {
                let maxSecs = Double(i.maxHours) * 3600.0
                if i.now - onSince >= maxSecs {
                    want = false
                    capped = true
                    reason = "hard cap \(i.maxHours)h reached — allowing sleep until idle"
                    reasonKey = "reason.hardCap"
                    reasonValues = [i.maxHours]
                } else {
                    (reason, reasonKey) = reasonForActive(i)
                }
            } else {
                (reason, reasonKey) = reasonForActive(i)
            }
        }

        // 2) Safety governors — can only turn OFF. First match wins. These run
        //    AFTER the state machine and deliberately do NOT reset onSince/
        //    capped: a battery/thermal cut is not an idle period, so when the
        //    condition clears the continuous-awake timer resumes where it was.
        if want && i.onBattery {
            if let pct = i.batteryPercent, pct <= i.criticalBatteryPercent {
                want = false
                reason = "critical battery \(pct)% ≤ \(i.criticalBatteryPercent)%"
                reasonKey = "reason.criticalBattery"
                reasonValues = [pct, i.criticalBatteryPercent]
            } else if let pct = i.batteryPercent, pct <= i.batteryFloorPercent {
                want = false
                reason = "battery \(pct)% ≤ floor \(i.batteryFloorPercent)%"
                reasonKey = "reason.batteryFloor"
                reasonValues = [pct, i.batteryFloorPercent]
            } else if i.acOnly {
                want = false
                reason = "AC-only mode — running on battery"
                reasonKey = "reason.acOnly"
                reasonValues = []
            }
        }
        if want && i.thermalSerious {
            want = false
            reason = "thermal pressure high — allowing sleep"
            reasonKey = "reason.thermal"
            reasonValues = []
        }

        return Decision(shouldStayAwake: want,
                        reason: reason,
                        reasonKey: reasonKey,
                        reasonValues: reasonValues,
                        onSince: onSince,
                        capped: capped)
    }

    /// Returns the English reason string and its stable localization key for an
    /// active (keep-awake) decision.
    private static func reasonForActive(_ i: DecisionInputs) -> (String, String) {
        if i.forceOn { return ("manual: keep awake", "reason.manualOn") }
        if i.sessionActive { return ("active agent session detected", "reason.activeSession") }
        if i.processActive { return ("watched process is busy", "reason.processBusy") }
        return ("keeping awake", "reason.keepAwake")
    }
}
