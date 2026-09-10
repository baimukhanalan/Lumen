import SwiftUI
import LumenCore

/// The Settings window content: four tabs bound to the shared config.
/// Light/dark aware automatically via system materials and semantic colors.
@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer
    /// Called when the user asks to (re)install or remove the daemon.
    var onInstall: () -> Void
    var onUninstall: () -> Void
    var daemonInstalled: Bool

    var body: some View {
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
        .frame(width: 460, height: 360)
        .padding()
    }
}

@available(macOS 12.0, *)
private struct GeneralTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Picker(loc.string("field.mode"), selection: $model.mode) {
                Text(loc.string("mode.auto")).tag(LumenMode.auto)
                Text(loc.string("mode.on")).tag(LumenMode.on)
                Text(loc.string("mode.off")).tag(LumenMode.off)
                Text(loc.string("mode.remote")).tag(LumenMode.remote)
            }
            Picker(loc.string("field.language"), selection: $model.language) {
                Text(loc.string("lang.system")).tag("system")
                Text("English").tag("en")
                Text("Русский").tag("ru")
                Text("Қазақша").tag("kk")
            }
            Stepper(value: $model.graceMinutes, in: 1...120) {
                Text(loc.string("field.grace") + ": \(model.graceMinutes) min")
            }
            Stepper(value: $model.pollSeconds, in: 5...300, step: 5) {
                Text(loc.string("field.poll") + ": \(model.pollSeconds) s")
            }
            Text(loc.string("hint.language"))
                .font(.footnote).foregroundColor(.secondary)
        }
        .padding()
    }
}

@available(macOS 12.0, *)
private struct TriggersTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Toggle(loc.string("field.watchClaude"), isOn: $model.watchClaude)
            Toggle(loc.string("field.watchCodex"), isOn: $model.watchCodex)
            Divider()
            Toggle(loc.string("field.processTriggers"), isOn: $model.enableProcessTriggers)
            Stepper(value: $model.cpuThresholdPercent, in: 1...100, step: 5) {
                Text(loc.string("field.cpuThreshold") + ": \(model.cpuThresholdPercent)%")
            }
            .disabled(!model.enableProcessTriggers)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.string("field.processList"))
                TextField("ollama, docker, node", text: $model.processListText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.enableProcessTriggers)
                Text(loc.string("hint.processList"))
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

@available(macOS 12.0, *)
private struct SafetyTab: View {
    @ObservedObject var model: ConfigModel
    let loc: Localizer

    var body: some View {
        Form {
            Stepper(value: $model.batteryFloorPercent, in: 0...100, step: 5) {
                Text(loc.string("field.batteryFloor") + ": \(model.batteryFloorPercent)%")
            }
            Stepper(value: $model.criticalBatteryPercent, in: 0...100, step: 5) {
                Text(loc.string("field.criticalBattery") + ": \(model.criticalBatteryPercent)%")
            }
            Stepper(value: $model.maxHours, in: 0...48) {
                Text(loc.string("field.maxHours") + ": " +
                     (model.maxHours == 0 ? loc.string("value.noLimit") : "\(model.maxHours) h"))
            }
            Toggle(loc.string("field.acOnly"), isOn: $model.acOnly)
            Text(loc.string("hint.safety"))
                .font(.footnote).foregroundColor(.secondary)
        }
        .padding()
    }
}

@available(macOS 12.0, *)
private struct AboutTab: View {
    let loc: Localizer
    let daemonInstalled: Bool
    var onInstall: () -> Void
    var onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("Lumen").font(.title2).bold()
                    Text("v\(LumenVersion.string)").foregroundColor(.secondary)
                }
            }
            Text(loc.string("about.tagline"))
                .foregroundColor(.secondary)
            Divider()
            HStack {
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
            Spacer()
            Text(loc.string("about.privilege"))
                .font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
