import SwiftUI
import Combine
import LumenCore

/// Publishes the daemon's live state + current config to the Settings UI,
/// refreshing on a timer so the status card stays current while open.
@available(macOS 12.0, *)
final class StatusModel: ObservableObject {
    @Published var state: DaemonState?
    @Published var config: LumenConfig = .defaults

    private let paths = Paths.forCurrentUser()
    private var timer: Timer?

    init() {
        reload()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reload()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    func reload() {
        state = StateStore.load(at: paths.stateFile)
        config = ConfigStore.load(at: paths.configFile)
    }
}

/// The Settings window content: a live status card plus four grouped tabs
/// bound to the shared config. Light/dark aware via semantic colors.
@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var model: ConfigModel
    @StateObject private var status = StatusModel()
    let loc: Localizer
    /// Called when the user asks to (re)install or remove the daemon.
    var onInstall: () -> Void
    var onUninstall: () -> Void
    var daemonInstalled: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusCard(status: status, loc: loc)
                .padding(16)

            TabView {
                GeneralTab(model: model, loc: loc)
                    .tabItem { Label(loc.string("tab.general"), systemImage: "gearshape") }
                TriggersTab(model: model, loc: loc)
                    .tabItem { Label(loc.string("tab.triggers"), systemImage: "bolt") }
                SafetyTab(model: model, loc: loc)
                    .tabItem { Label(loc.string("tab.safety"), systemImage: "shield") }
                AboutTab(loc: loc,
                         daemonInstalled: daemonInstalled,
                         onInstall: onInstall,
                         onUninstall: onUninstall)
                    .tabItem { Label(loc.string("tab.about"), systemImage: "info.circle") }
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - Live status card

@available(macOS 12.0, *)
private struct StatusCard: View {
    @ObservedObject var status: StatusModel
    let loc: Localizer

    private var pres: StatePresentation {
        StatePresentation.resolve(config: status.config, state: status.state, loc: loc)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: pres.ui.tint).opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: pres.ui.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color(nsColor: pres.ui.tint))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(pres.title)
                        .font(.title3).bold()
                        .foregroundColor(.primary)
                    Text(pres.reason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()

            HStack(alignment: .top, spacing: 0) {
                metric(label: loc.string("field.mode"), value: modeLabel)
                divider
                metric(label: loc.string("label.battery"), value: batteryLabel)
                divider
                metric(label: loc.string("label.thermal"), value: thermalLabel)
                divider
                metric(label: loc.string("label.session"), value: sessionLabel)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 30)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var modeLabel: String {
        switch status.config.mode {
        case .auto:   return loc.string("mode.auto")
        case .on:     return loc.string("mode.on")
        case .off:    return loc.string("mode.off")
        case .remote: return loc.string("mode.remote")
        }
    }

    private var batteryLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        if let pct = state.batteryPercent {
            let src = state.onBattery ? "🔋" : "⚡︎"
            return "\(pct)% \(src)"
        }
        return state.onBattery ? loc.string("value.onBattery") : loc.string("value.onAC")
    }

    private var thermalLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        return StatePresentation.thermalLabel(state.thermal, loc: loc)
    }

    private var sessionLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        let detected = state.sessionActive || state.processActive
        return loc.string(detected ? "value.yes" : "value.no")
    }
}

// MARK: - Reusable rows

@available(macOS 12.0, *)
private struct HelperText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

@available(macOS 12.0, *)
private struct GeneralTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Section(header: Text(loc.string("section.behavior"))) {
                Picker(loc.string("field.mode"), selection: $model.mode) {
                    Text(loc.string("mode.auto")).tag(LumenMode.auto)
                    Text(loc.string("mode.on")).tag(LumenMode.on)
                    Text(loc.string("mode.off")).tag(LumenMode.off)
                    Text(loc.string("mode.remote")).tag(LumenMode.remote)
                }
                HelperText(text: loc.string("hint.mode"))
            }

            Section(header: Text(loc.string("section.timing"))) {
                Stepper(value: $model.graceMinutes, in: 1...120) {
                    LabeledContentRow(label: loc.string("field.grace"),
                                      value: "\(model.graceMinutes) min")
                }
                Stepper(value: $model.pollSeconds, in: 5...300, step: 5) {
                    LabeledContentRow(label: loc.string("field.poll"),
                                      value: "\(model.pollSeconds) s")
                }
                HelperText(text: loc.string("hint.timing"))
            }

            Section(header: Text(loc.string("section.appearance"))) {
                Picker(loc.string("field.language"), selection: $model.language) {
                    Text(loc.string("lang.system")).tag("system")
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                    Text("Қазақша").tag("kk")
                }
                HelperText(text: loc.string("hint.language"))
            }
        }
        .formStyleGrouped()
    }
}

// MARK: - Triggers

@available(macOS 12.0, *)
private struct TriggersTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Section(header: Text(loc.string("section.sessions"))) {
                Toggle(loc.string("field.watchClaude"), isOn: $model.watchClaude)
                Toggle(loc.string("field.watchCodex"), isOn: $model.watchCodex)
                HelperText(text: loc.string("hint.sessions"))
            }

            Section(header: Text(loc.string("section.processes"))) {
                Toggle(loc.string("field.processTriggers"), isOn: $model.enableProcessTriggers)
                Stepper(value: $model.cpuThresholdPercent, in: 1...100, step: 5) {
                    LabeledContentRow(label: loc.string("field.cpuThreshold"),
                                      value: "\(model.cpuThresholdPercent)%")
                }
                .disabled(!model.enableProcessTriggers)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.string("field.processList"))
                    TextField("ollama, docker, node", text: $model.processListText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.enableProcessTriggers)
                    HelperText(text: loc.string("hint.processList"))
                }
            }
        }
        .formStyleGrouped()
    }
}

// MARK: - Safety

@available(macOS 12.0, *)
private struct SafetyTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Section(header: Text(loc.string("section.power"))) {
                Stepper(value: $model.batteryFloorPercent, in: 0...100, step: 5) {
                    LabeledContentRow(label: loc.string("field.batteryFloor"),
                                      value: "\(model.batteryFloorPercent)%")
                }
                Stepper(value: $model.criticalBatteryPercent, in: 0...100, step: 5) {
                    LabeledContentRow(label: loc.string("field.criticalBattery"),
                                      value: "\(model.criticalBatteryPercent)%")
                }
                Toggle(loc.string("field.acOnly"), isOn: $model.acOnly)
            }

            Section(header: Text(loc.string("section.duration"))) {
                Stepper(value: $model.maxHours, in: 0...48) {
                    LabeledContentRow(
                        label: loc.string("field.maxHours"),
                        value: model.maxHours == 0 ? loc.string("value.noLimit")
                                                   : "\(model.maxHours) h")
                }
                HelperText(text: loc.string("hint.safety"))
            }
        }
        .formStyleGrouped()
    }
}

// MARK: - About

@available(macOS 12.0, *)
private struct AboutTab: View {
    let loc: Localizer
    let daemonInstalled: Bool
    var onInstall: () -> Void
    var onUninstall: () -> Void

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? LumenVersion.string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumen").font(.title2).bold()
                    Text("v\(version)").foregroundColor(.secondary)
                }
            }

            Text(loc.string("about.tagline"))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(daemonInstalled ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(daemonInstalled ? loc.string("about.daemonInstalled")
                                     : loc.string("about.daemonMissing"))
            }
            HStack {
                Button(daemonInstalled ? loc.string("about.reinstall")
                                       : loc.string("about.install"),
                       action: onInstall)
                if daemonInstalled {
                    Button(loc.string("about.uninstall"), action: onUninstall)
                }
            }

            Link(destination: URL(string: "https://github.com/baimukhanalan/Lumen")!) {
                Label(loc.string("about.github"), systemImage: "arrow.up.right.square")
            }

            Spacer()

            Text(loc.string("about.privilege"))
                .font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

// MARK: - Small layout helper

/// A label on the left, its current value trailing — used inside steppers so
/// the number is always visible.
@available(macOS 12.0, *)
private struct LabeledContentRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - formStyle compatibility

@available(macOS 12.0, *)
private extension View {
    /// `.formStyle(.grouped)` only exists on macOS 13+. Fall back gracefully on
    /// macOS 12 where `Form` already renders acceptably.
    @ViewBuilder
    func formStyleGrouped() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped)
        } else {
            self
        }
    }
}
