import AppKit
import LumenCore

/// Owns the menu-bar `NSStatusItem`: the live-state icon and the status menu.
/// Polls the daemon's state file to keep the icon and status line current.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let loc: Localizer
    private let paths = Paths.forCurrentUser()

    private let onOpenSettings: () -> Void
    private let onInstall: () -> Void

    private var pollTimer: Timer?

    // Menu items we mutate on refresh.
    private let statusLine = NSMenuItem()
    private let reasonLine = NSMenuItem()
    private var modeItems: [LumenMode: NSMenuItem] = [:]
    private let stopTimedItem = NSMenuItem()

    /// Visual states for the icon.
    private enum IconState { case awake, armed, paused, unavailable }

    init(loc: Localizer,
         onOpenSettings: @escaping () -> Void,
         onInstall: @escaping () -> Void) {
        self.loc = loc
        self.onOpenSettings = onOpenSettings
        self.onInstall = onInstall
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        refresh()
        startPolling()
    }

    deinit { pollTimer?.invalidate() }

    // MARK: - Menu construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusLine.isEnabled = false
        reasonLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(reasonLine)
        menu.addItem(.separator())

        // Modes (radio-style checkmarks).
        addModeItem(to: menu, mode: .auto, key: "mode.auto", keyEquivalent: "1")
        addModeItem(to: menu, mode: .on, key: "mode.on", keyEquivalent: "2")
        addModeItem(to: menu, mode: .off, key: "mode.off", keyEquivalent: "3")
        addModeItem(to: menu, mode: .remote, key: "mode.remote", keyEquivalent: "4")
        menu.addItem(.separator())

        // Timed session submenu.
        let timed = NSMenuItem(title: loc.string("menu.timed"), action: nil, keyEquivalent: "")
        let timedMenu = NSMenu()
        for (index, preset) in ControlWriter.timedPresets.enumerated() {
            let item = NSMenuItem(title: loc.string(preset.labelKey),
                                  action: #selector(startTimed(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            timedMenu.addItem(item)
        }
        timedMenu.addItem(.separator())
        stopTimedItem.title = loc.string("menu.timedStop")
        stopTimedItem.action = #selector(stopTimed)
        stopTimedItem.target = self
        timedMenu.addItem(stopTimedItem)
        timed.submenu = timedMenu
        menu.addItem(timed)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: loc.string("menu.settings"),
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: loc.string("menu.quit"),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addModeItem(to menu: NSMenu, mode: LumenMode, key: String, keyEquivalent: String) {
        let item = NSMenuItem(title: loc.string(key),
                              action: #selector(changeMode(_:)), keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = mode.rawValue
        modeItems[mode] = item
        menu.addItem(item)
    }

    // MARK: - Polling & refresh

    private func startPolling() {
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Refresh the menu (also called by `menuNeedsUpdate`).
    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let config = ConfigStore.load(at: paths.configFile)
        let state = StateStore.load(at: paths.stateFile)
        let fresh = isFresh(state)

        // Icon + status text.
        let iconState = resolveIconState(config: config, state: state, fresh: fresh)
        applyIcon(iconState)
        statusLine.title = statusText(iconState: iconState, config: config, state: state, fresh: fresh)
        reasonLine.title = reasonText(state: state, fresh: fresh, config: config)

        // Mode checkmarks.
        for (mode, item) in modeItems {
            item.state = (config.mode == mode) ? .on : .off
        }

        // Timed session UI.
        let timedActive = config.timedUntil > Date().timeIntervalSince1970
        stopTimedItem.isHidden = !timedActive
    }

    private func isFresh(_ state: DaemonState?) -> Bool {
        guard let state else { return false }
        // Consider stale if older than ~4 polls (defensive; daemon may be down).
        return Date().timeIntervalSince1970 - state.updatedAt < 90
    }

    private func resolveIconState(config: LumenConfig, state: DaemonState?, fresh: Bool) -> IconState {
        guard fresh, let state else {
            return PrivilegedInstaller.isInstalled ? .armed : .unavailable
        }
        if config.mode == .off { return .paused }
        if state.sleepDisabled { return .awake }
        return .armed
    }

    private func applyIcon(_ state: IconState) {
        let symbol: String
        switch state {
        case .awake: symbol = "bolt.fill"
        case .armed: symbol = "eye"
        case .paused: symbol = "moon.zzz.fill"
        case .unavailable: symbol = "exclamationmark.triangle"
        }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lumen") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "L"
        }
    }

    private func statusText(iconState: IconState, config: LumenConfig,
                            state: DaemonState?, fresh: Bool) -> String {
        switch iconState {
        case .unavailable: return loc.string("status.notRunning")
        case .paused: return loc.string("status.paused")
        case .awake: return loc.string("status.awake")
        case .armed: return loc.string("status.armed")
        }
    }

    private func reasonText(state: DaemonState?, fresh: Bool, config: LumenConfig) -> String {
        if !fresh || state == nil {
            return PrivilegedInstaller.isInstalled
                ? loc.string("reason.waiting")
                : loc.string("reason.notInstalled")
        }
        guard let state else { return "" }
        var detail = state.reason
        if let pct = state.batteryPercent {
            detail += state.onBattery ? "  ·  \(pct)% 🔋" : "  ·  \(pct)% ⚡︎"
        }
        return detail
    }

    // MARK: - Actions

    @objc private func changeMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = LumenMode(rawValue: raw) else { return }
        ControlWriter.setMode(mode)
        refresh()
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        let presets = ControlWriter.timedPresets
        guard sender.tag >= 0, sender.tag < presets.count else { return }
        ControlWriter.startTimedSession(seconds: presets[sender.tag].seconds)
        refresh()
    }

    @objc private func stopTimed() {
        ControlWriter.stopTimedSession()
        refresh()
    }

    @objc private func openSettings() { onOpenSettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}
