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

/// The sections shown in the settings sidebar.
@available(macOS 12.0, *)
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, triggers, safety, about
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .general:  return "tab.general"
        case .triggers: return "tab.triggers"
        case .safety:   return "tab.safety"
        case .about:    return "tab.about"
        }
    }

    var symbol: String {
        switch self {
        case .general:  return "gearshape.fill"
        case .triggers: return "bolt.fill"
        case .safety:   return "shield.lefthalf.filled"
        case .about:    return "info.circle.fill"
        }
    }
}

/// Holds the currently selected sidebar section. A tiny `ObservableObject`
/// (rather than `@State`) so it compiles under the Command-Line-Tools toolchain,
/// which cannot load the SwiftUI property-wrapper macros.
@available(macOS 12.0, *)
private final class SettingsNav: ObservableObject {
    @Published var section: SettingsSection = .general
}

/// The Settings window content: a left sidebar of sections, a live status
/// "hero" card that stays visible, and the selected section's controls. Fully
/// light/dark aware via semantic colors and reactive to language changes.
@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n
    @StateObject private var status = StatusModel()
    @StateObject private var nav = SettingsNav()
    /// Called when the user asks to (re)install or remove the daemon.
    var onInstall: () -> Void
    var onUninstall: () -> Void
    var daemonInstalled: Bool

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav, l10n: l10n)
                .frame(width: 208)

            Divider()

            VStack(spacing: 0) {
                StatusCard(status: status, l10n: l10n)
                    .padding(20)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detail
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.section {
        case .general:  GeneralSection(model: model, l10n: l10n)
        case .triggers: TriggersSection(model: model, l10n: l10n)
        case .safety:   SafetySection(model: model, l10n: l10n)
        case .about:    AboutSection(l10n: l10n,
                                     daemonInstalled: daemonInstalled,
                                     onInstall: onInstall,
                                     onUninstall: onUninstall)
        }
    }
}

// MARK: - Sidebar

@available(macOS 12.0, *)
private struct Sidebar: View {
    @ObservedObject var nav: SettingsNav
    @ObservedObject var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // App identity.
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lumen")
                        .font(.system(size: 15, weight: .bold))
                    Text("v\(SettingsView.appVersion)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ForEach(SettingsSection.allCases) { item in
                SidebarRow(
                    title: l10n.t(item.titleKey),
                    symbol: item.symbol,
                    selected: nav.section == item,
                    action: { nav.section = item }
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    /// A slightly recessed sidebar surface that reads correctly in both themes.
    private var sidebarBackground: some View {
        Color(nsColor: .underPageBackgroundColor)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.4))
                    .frame(width: 1)
            }
    }
}

@available(macOS 12.0, *)
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, alignment: .center)
                    .foregroundColor(selected ? .white : .accentColor)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

// MARK: - Live status hero card

@available(macOS 12.0, *)
private struct StatusCard: View {
    @ObservedObject var status: StatusModel
    @ObservedObject var l10n: L10n

    private var pres: StatePresentation {
        StatePresentation.resolve(config: status.config, state: status.state, loc: l10n)
    }

    var body: some View {
        let tint = Color(nsColor: pres.ui.tint)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // State icon in a tinted, softly gradient-filled tile.
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                        .frame(width: 60, height: 60)
                    Image(systemName: pres.ui.symbol)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(pres.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pres.reason)
                        .font(.system(size: 12.5))
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
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.8))
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

// MARK: - Reusable building blocks

/// A titled, hairline-bordered card that groups related controls. Rows are laid
/// out by the caller; use `RowDivider` between them for the inset separator.
@available(macOS 12.0, *)
private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            )
        }
    }
}

/// An inset hairline between two rows inside a `Card`.
@available(macOS 12.0, *)
private struct RowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.6))
            .padding(.leading, 16)
    }
}

/// A standard control row: a leading label (with optional subtitle) and a
/// trailing control the caller supplies.
@available(macOS 12.0, *)
private struct ControlRow<Trailing: View>: View {
    let label: String
    var subtitle: String? = nil
    var enabled: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(enabled ? .primary : .secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// A trailing value + stepper pairing used for numeric rows.
@available(macOS 12.0, *)
private struct StepperRow: View {
    let label: String
    let value: String
    var enabled: Bool = true
    let range: ClosedRange<Int>
    var step: Int = 1
    @Binding var binding: Int

    var body: some View {
        ControlRow(label: label, enabled: enabled) {
            HStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(enabled ? .primary : .secondary)
                Stepper("", value: $binding, in: range, step: step)
                    .labelsHidden()
                    .disabled(!enabled)
            }
        }
    }
}

/// A trailing switch row.
@available(macOS 12.0, *)
private struct SwitchRow: View {
    let label: String
    var subtitle: String? = nil
    var enabled: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        ControlRow(label: label, subtitle: subtitle, enabled: enabled) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
    }
}

/// A short helper caption shown beneath a card.
@available(macOS 12.0, *)
private struct Helper: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 2)
            .padding(.top, -2)
    }
}

// MARK: - General

@available(macOS 12.0, *)
private struct GeneralSection: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    var body: some View {
        Card(title: l10n.t("section.behavior"), symbol: "power") {
            ModeRow(mode: .auto, icon: "sparkles", tint: .accentColor,
                    model: model, l10n: l10n)
            RowDivider()
            ModeRow(mode: .on, icon: "bolt.fill", tint: Color(nsColor: .systemYellow),
                    model: model, l10n: l10n)
            RowDivider()
            ModeRow(mode: .off, icon: "moon.fill", tint: Color(nsColor: .systemGray),
                    model: model, l10n: l10n)
            RowDivider()
            ModeRow(mode: .remote, icon: "antenna.radiowaves.left.and.right",
                    tint: Color(nsColor: .systemPurple),
                    model: model, l10n: l10n)
        }

        Card(title: l10n.t("section.timing"), symbol: "timer") {
            StepperRow(label: l10n.t("field.grace"),
                       value: "\(model.graceMinutes) \(l10n.t("unit.min"))",
                       range: 1...120,
                       binding: $model.graceMinutes)
            RowDivider()
            StepperRow(label: l10n.t("field.poll"),
                       value: "\(model.pollSeconds) \(l10n.t("unit.sec"))",
                       range: 5...300, step: 5,
                       binding: $model.pollSeconds)
        }
        Helper(text: l10n.t("hint.timing"))

        Card(title: l10n.t("section.appearance"), symbol: "globe") {
            ControlRow(label: l10n.t("field.language")) {
                Picker("", selection: $model.language) {
                    Text(l10n.t("lang.system")).tag("system")
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                    Text("Қазақша").tag("kk")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: model.language) { newValue in
                    // Live-switch the UI now; `model.language` also persists to
                    // config.json via its own didSet, so it survives relaunch.
                    l10n.setLanguage(newValue)
                }
            }
        }
        Helper(text: l10n.t("hint.language"))
    }
}

/// A selectable keep-awake mode with icon, title, human description and a radio
/// indicator — a richer, more premium alternative to a plain picker.
@available(macOS 12.0, *)
private struct ModeRow: View {
    let mode: LumenMode
    let icon: String
    let tint: Color
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    private var selected: Bool { model.mode == mode }

    private var titleKey: String {
        switch mode {
        case .auto: return "mode.auto"
        case .on: return "mode.on"
        case .off: return "mode.off"
        case .remote: return "mode.remote"
        }
    }
    private var descKey: String { titleKey + ".desc" }

    var body: some View {
        Button(action: { model.mode = mode }) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(selected ? 0.22 : 0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t(titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(l10n.t(descKey))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(selected ? .accentColor
                                              : Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(selected
                        ? Color.accentColor.opacity(0.08)
                        : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Triggers

@available(macOS 12.0, *)
private struct TriggersSection: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    var body: some View {
        Card(title: l10n.t("section.sessions"), symbol: "terminal") {
            SwitchRow(label: l10n.t("field.watchClaude"), isOn: $model.watchClaude)
            RowDivider()
            SwitchRow(label: l10n.t("field.watchCodex"), isOn: $model.watchCodex)
        }
        Helper(text: l10n.t("hint.sessions"))

        Card(title: l10n.t("section.processes"), symbol: "cpu") {
            SwitchRow(label: l10n.t("field.processTriggers"), isOn: $model.enableProcessTriggers)
            RowDivider()
            StepperRow(label: l10n.t("field.cpuThreshold"),
                       value: "\(model.cpuThresholdPercent)%",
                       enabled: model.enableProcessTriggers,
                       range: 1...100, step: 5,
                       binding: $model.cpuThresholdPercent)
            RowDivider()
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.t("field.processList"))
                    .font(.system(size: 13))
                    .foregroundColor(model.enableProcessTriggers ? .primary : .secondary)
                TextField("ollama, docker, node", text: $model.processListText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.enableProcessTriggers)
                Text(l10n.t("hint.processList"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Safety

@available(macOS 12.0, *)
private struct SafetySection: View {
    @ObservedObject var model: ConfigModel
    @ObservedObject var l10n: L10n

    var body: some View {
        Card(title: l10n.t("section.power"), symbol: "battery.50") {
            StepperRow(label: l10n.t("field.batteryFloor"),
                       value: "\(model.batteryFloorPercent)%",
                       range: 0...100, step: 5,
                       binding: $model.batteryFloorPercent)
            RowDivider()
            StepperRow(label: l10n.t("field.criticalBattery"),
                       value: "\(model.criticalBatteryPercent)%",
                       range: 0...100, step: 5,
                       binding: $model.criticalBatteryPercent)
            RowDivider()
            SwitchRow(label: l10n.t("field.acOnly"), isOn: $model.acOnly)
        }

        Card(title: l10n.t("section.duration"), symbol: "hourglass") {
            StepperRow(
                label: l10n.t("field.maxHours"),
                value: model.maxHours == 0 ? l10n.t("value.noLimit")
                                           : "\(model.maxHours) \(l10n.t("unit.hour"))",
                range: 0...48,
                binding: $model.maxHours)
        }
        Helper(text: l10n.t("hint.safety"))
    }
}

// MARK: - About

@available(macOS 12.0, *)
private struct AboutSection: View {
    @ObservedObject var l10n: L10n
    let daemonInstalled: Bool
    var onInstall: () -> Void
    var onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Identity.
            HStack(spacing: 14) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 46))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lumen").font(.system(size: 24, weight: .bold))
                    Text("v\(SettingsView.appVersion)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(l10n.t("about.tagline"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Background-helper status + actions.
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(daemonInstalled ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(daemonInstalled ? l10n.t("about.daemonInstalled")
                                         : l10n.t("about.daemonMissing"))
                        .font(.system(size: 13, weight: .medium))
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
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            )

            Link(destination: URL(string: "https://github.com/baimukhanalan/Lumen")!) {
                Label(l10n.t("about.github"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.link)

            Text(l10n.t("about.privilege"))
                .font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shared helpers

@available(macOS 12.0, *)
extension SettingsView {
    /// App version from the bundle, falling back to the compiled-in string.
    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? LumenVersion.string
    }
}
