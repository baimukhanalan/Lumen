import AppKit
import LumenCore

/// The four visual states Lumen surfaces, shared by the menu-bar icon, the
/// menu header, and the Settings status card so they always agree.
enum LumenUIState {
    case awake        // keeping the Mac awake (sleep disabled)
    case armed        // watching for activity; sleep currently allowed
    case paused       // user forced allow-sleep
    case unavailable  // daemon not installed / not reporting

    /// SF Symbol name for this state.
    var symbol: String {
        switch self {
        case .awake:       return "bolt.fill"
        case .armed:       return "eye.fill"
        case .paused:      return "pause.circle.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    /// Accent colour used for the icon in the Settings card (the menu-bar icon
    /// stays a monochrome template to match the system).
    var tint: NSColor {
        switch self {
        case .awake:       return .systemYellow
        case .armed:       return .systemGreen
        case .paused:      return .systemGray
        case .unavailable: return .systemOrange
        }
    }
}

/// Derives a presentable state (icon + one-line title + reason detail) from the
/// current config and the daemon's published state.
struct StatePresentation {

    let ui: LumenUIState
    let title: String
    let reason: String

    /// Whether the daemon's state file is recent enough to trust.
    static func isFresh(_ state: DaemonState?) -> Bool {
        guard let state else { return false }
        return Date().timeIntervalSince1970 - state.updatedAt < 90
    }

    static func resolve(config: LumenConfig,
                        state: DaemonState?,
                        loc: L10n) -> StatePresentation {
        let fresh = isFresh(state)

        // Resolve the visual state.
        let ui: LumenUIState
        if !fresh || state == nil {
            ui = PrivilegedInstaller.isInstalled ? .armed : .unavailable
        } else if config.mode == .off {
            ui = .paused
        } else if state!.sleepDisabled {
            ui = .awake
        } else {
            ui = .armed
        }

        // Title.
        let title: String
        switch ui {
        case .unavailable: title = loc.t("status.notRunning")
        case .paused:      title = loc.t("status.paused")
        case .awake:       title = loc.t("status.awake")
        case .armed:       title = loc.t("status.armed")
        }

        // Reason detail line.
        let reason: String
        if !fresh || state == nil {
            reason = PrivilegedInstaller.isInstalled
                ? loc.t("reason.waiting")
                : loc.t("reason.notInstalled")
        } else {
            reason = localizedReason(state!, loc: loc)
        }

        return StatePresentation(ui: ui, title: title, reason: reason)
    }

    /// Localizes the daemon's stable `reasonKey` (interpolating any numeric
    /// args), falling back to the raw English `reason` string when the key is
    /// missing or unknown to the current string tables.
    static func localizedReason(_ state: DaemonState, loc: L10n) -> String {
        guard let key = state.reasonKey, !key.isEmpty else {
            return state.reason
        }
        let template = loc.t(key)
        // `L10n.t` returns the key itself when it is absent from every table,
        // which means we can't localize it — fall back to the English reason.
        if template == key {
            return state.reason
        }
        let values = state.reasonValues ?? []
        if values.isEmpty {
            return template
        }
        // Match `%d` specifiers with 32-bit ints so multi-arg formats align.
        let args = values.map { CInt($0) as CVarArg }
        return String(format: template, arguments: args)
    }

    /// Localized thermal label from the daemon's raw thermal string.
    static func thermalLabel(_ raw: String, loc: L10n) -> String {
        switch raw {
        case "fair":     return loc.t("thermal.fair")
        case "serious":  return loc.t("thermal.serious")
        case "critical": return loc.t("thermal.critical")
        default:         return loc.t("thermal.nominal")
        }
    }
}
