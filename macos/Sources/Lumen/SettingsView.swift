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
/// bound to the shared config. Light/dark aware via semantic colors, and fully
/// reactive to language changes via the shared `L10n` manager.
@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n
    @StateObject private var status = StatusModel()
    /// Called when the user asks to (re)install or remove the daemon.
    var onInstall: () -> Void
    var onUninstall: () -> Void
    var daemonInstalled: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusCard(status: status, l10n: l10n)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            TabView {
                GeneralTab(model: model, l10n: l10n)
                    .tabItem { Label(l10n.t("tab.general"), systemImage: "gearshape") }
                TriggersTab(model: model, l10n: l10n)
                    .tabItem { Label(l10n.t("tab.triggers"), systemImage: "bolt") }
                SafetyTab(model: model, l10n: l10n)
                    .tabItem { Label(l10n.t("tab.safety"), systemImage: "shield") }
                AboutTab(l10n: l10n,
                         daemonInstalled: daemonInstalled,
                         onInstall: onInstall,
                         onUninstall: onUninstall)
                    .tabItem { Label(l10n.t("tab.about"), systemImage: "info.circle") }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 600, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Live status card

@available(macOS 12.0, *)
private struct StatusCard: View {
    @ObservedObject var status: StatusModel
    @ObservedObject var l10n: L10n

    private var pres: StatePresentation {
        StatePresentation.resolve(config: status.config, state: status.state, loc: l10n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: pres.ui.tint).opacity(0.18))
                        .frame(width: 58, height: 58)
                    Image(systemName: pres.ui.symbol)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundColor(Color(nsColor: pres.ui.tint))
                }
                VStack(alignment: .leading, spacing: 4) {
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
                metric(label: l10n.t("field.mode"), value: modeLabel)
                divider
                metric(label: l10n.t("label.battery"), value: batteryLabel)
                divider
                metric(label: l10n.t("label.thermal"), value: thermalLabel)
                divider
                metric(label: l10n.t("label.session"), value: sessionLabel)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 34)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private var modeLabel: String {
        switch status.config.mode {
        case .auto:   return l10n.t("mode.auto")
        case .on:     return l10n.t("mode.on")
        case .off:    return l10n.t("mode.off")
        case .remote: return l10n.t("mode.remote")
        }
    }

    private var batteryLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        if let pct = state.batteryPercent {
            let src = state.onBattery ? "🔋" : "⚡︎"
            return "\(pct)% \(src)"
        }
        return state.onBattery ? l10n.t("value.onBattery") : l10n.t("value.onAC")
    }

    private var thermalLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        return StatePresentation.thermalLabel(state.thermal, loc: l10n)
    }

    private var sessionLabel: String {
        guard let state = status.state, StatePresentation.isFresh(state) else { return "—" }
        let detected = state.sessionActive || state.processActive
        return l10n.t(detected ? "value.yes" : "value.no")
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

/// A section header with an SF Symbol accent, matching native grouped forms.
@available(macOS 12.0, *)
private struct SectionHeader: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundColor(.secondary)
    }
}

// MARK: - General

@available(macOS 12.0, *)
private struct GeneralTab: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    var body: some View {
        Form {
            Section(header: SectionHeader(title: l10n.t("section.behavior"), symbol: "power")) {
                Picker(l10n.t("field.mode"), selection: $model.mode) {
                    Text(l10n.t("mode.auto")).tag(LumenMode.auto)
                    Text(l10n.t("mode.on")).tag(LumenMode.on)
                    Text(l10n.t("mode.off")).tag(LumenMode.off)
                    Text(l10n.t("mode.remote")).tag(LumenMode.remote)
                }
                HelperText(text: l10n.t("hint.mode"))
            }

            Section(header: SectionHeader(title: l10n.t("section.timing"), symbol: "timer")) {
                Stepper(value: $model.graceMinutes, in: 1...120) {
                    LabeledContentRow(label: l10n.t("field.grace"),
                                      value: "\(model.graceMinutes) \(l10n.t("unit.min"))")
                }
                Stepper(value: $model.pollSeconds, in: 5...300, step: 5) {
                    LabeledContentRow(label: l10n.t("field.poll"),
                                      value: "\(model.pollSeconds) \(l10n.t("unit.sec"))")
                }
                HelperText(text: l10n.t("hint.timing"))
            }

            Section(header: SectionHeader(title: l10n.t("section.appearance"), symbol: "globe")) {
                Picker(l10n.t("field.language"), selection: $model.language) {
                    Text(l10n.t("lang.system")).tag("system")
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                    Text("Қазақша").tag("kk")
                }
                .onChange(of: model.language) { newValue in
                    // Live-switch the UI now; `model.language` also persists to
                    // config.json via its own didSet, so it survives relaunch.
                    l10n.setLanguage(newValue)
                }
                HelperText(text: l10n.t("hint.language"))
            }
        }
        .formStyleGrouped()
    }
}

// MARK: - Triggers

@available(macOS 12.0, *)
private struct TriggersTab: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    var body: some View {
        Form {
            Section(header: SectionHeader(title: l10n.t("section.sessions"), symbol: "terminal")) {
                Toggle(l10n.t("field.watchClaude"), isOn: $model.watchClaude)
                Toggle(l10n.t("field.watchCodex"), isOn: $model.watchCodex)
                HelperText(text: l10n.t("hint.sessions"))
            }

            Section(header: SectionHeader(title: l10n.t("section.processes"), symbol: "cpu")) {
                Toggle(l10n.t("field.processTriggers"), isOn: $model.enableProcessTriggers)
                Stepper(value: $model.cpuThresholdPercent, in: 1...100, step: 5) {
                    LabeledContentRow(label: l10n.t("field.cpuThreshold"),
                                      value: "\(model.cpuThresholdPercent)%")
                }
                .disabled(!model.enableProcessTriggers)
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.t("field.processList"))
                        .foregroundColor(model.enableProcessTriggers ? .primary : .secondary)
                    TextField("ollama, docker, node", text: $model.processListText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.enableProcessTriggers)
                    HelperText(text: l10n.t("hint.processList"))
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
    @ObservedObject var l10n: L10n

    var body: some View {
        Form {
            Section(header: SectionHeader(title: l10n.t("section.power"), symbol: "battery.50")) {
                Stepper(value: $model.batteryFloorPercent, in: 0...100, step: 5) {
                    LabeledContentRow(label: l10n.t("field.batteryFloor"),
                                      value: "\(model.batteryFloorPercent)%")
                }
                Stepper(value: $model.criticalBatteryPercent, in: 0...100, step: 5) {
                    LabeledContentRow(label: l10n.t("field.criticalBattery"),
                                      value: "\(model.criticalBatteryPercent)%")
                }
                Toggle(l10n.t("field.acOnly"), isOn: $model.acOnly)
            }

            Section(header: SectionHeader(title: l10n.t("section.duration"), symbol: "hourglass")) {
                Stepper(value: $model.maxHours, in: 0...48) {
                    LabeledContentRow(
                        label: l10n.t("field.maxHours"),
                        value: model.maxHours == 0 ? l10n.t("value.noLimit")
                                                   : "\(model.maxHours) \(l10n.t("unit.hour"))")
                }
                HelperText(text: l10n.t("hint.safety"))
            }
        }
        .formStyleGrouped()
    }
}

// MARK: - About

@available(macOS 12.0, *)
private struct AboutTab: View {
    @ObservedObject var l10n: L10n
    let daemonInstalled: Bool
    var onInstall: () -> Void
    var onUninstall: () -> Void

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? LumenVersion.string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Identity.
            HStack(spacing: 14) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 46))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lumen").font(.title).bold()
                    Text("v\(version)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(l10n.t("about.tagline"))
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Daemon status card.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(daemonInstalled ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(daemonInstalled ? l10n.t("about.daemonInstalled")
                                         : l10n.t("about.daemonMissing"))
                        .font(.callout).fontWeight(.medium)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button(daemonInstalled ? l10n.t("about.reinstall")
                                           : l10n.t("about.install"),
                           action: onInstall)
                    if daemonInstalled {
                        Button(l10n.t("about.uninstall"), action: onUninstall)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Link(destination: URL(string: "https://github.com/baimukhanalan/Lumen")!) {
                Label(l10n.t("about.github"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.link)

            Spacer(minLength: 0)

            Text(l10n.t("about.privilege"))
                .font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
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
