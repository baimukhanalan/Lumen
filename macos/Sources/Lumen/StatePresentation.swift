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
                        loc: Localizer) -> StatePresentation {
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
        case .unavailable: title = loc.string("status.notRunning")
        case .paused:      title = loc.string("status.paused")
        case .awake:       title = loc.string("status.awake")
        case .armed:       title = loc.string("status.armed")
        }

        // Reason detail line.
        let reason: String
        if !fresh || state == nil {
            reason = PrivilegedInstaller.isInstalled
                ? loc.string("reason.waiting")
                : loc.string("reason.notInstalled")
        } else {
            reason = state!.reason
        }

        return StatePresentation(ui: ui, title: title, reason: reason)
    }

    /// Localized thermal label from the daemon's raw thermal string.
    static func thermalLabel(_ raw: String, loc: Localizer) -> String {
        switch raw {
        case "fair":     return loc.string("thermal.fair")
        case "serious":  return loc.string("thermal.serious")
        case "critical": return loc.string("thermal.critical")
        default:         return loc.string("thermal.nominal")
        }
    }
}
