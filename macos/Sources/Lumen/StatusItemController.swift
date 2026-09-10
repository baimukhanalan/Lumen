import AppKit
import LumenCore

/// Owns the menu-bar `NSStatusItem`: the live-state icon and the status menu.
/// Polls the daemon's state file to keep the icon and status header current.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let loc: Localizer
    private let paths = Paths.forCurrentUser()

    private let onOpenSettings: () -> Void
    private let onInstall: () -> Void

    private var pollTimer: Timer?

    // Items we mutate on refresh.
    private let headerItem = NSMenuItem()
    private var modeItems: [LumenMode: NSMenuItem] = [:]
    private let stopTimedItem = NSMenuItem()

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

        // Rich, non-clickable status header (icon + title + detail lines).
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Modes (radio-style checkmarks).
        addModeItem(to: menu, mode: .auto, key: "mode.auto", keyEquivalent: "1")
        addModeItem(to: menu, mode: .on, key: "mode.on", keyEquivalent: "2")
        addModeItem(to: menu, mode: .off, key: "mode.off", keyEquivalent: "3")
        addModeItem(to: menu, mode: .remote, key: "mode.remote", keyEquivalent: "4")
        menu.addItem(.separator())

        // Timed session submenu.
        let timed = NSMenuItem(title: loc.string("menu.timed"), action: nil, keyEquivalent: "")
        timed.image = symbolImage("timer", pointSize: 13)
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

        let settings = NSMenuItem(title: loc.string("menu.open"),
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = symbolImage("slider.horizontal.3", pointSize: 13)
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
        let pres = StatePresentation.resolve(config: config, state: state, loc: loc)

        // Menu-bar icon: monochrome template symbol reflecting the state.
        applyIcon(pres.ui)

        // Rich header: tinted symbol + bold title + secondary detail lines.
        headerItem.image = symbolImage(pres.ui.symbol, pointSize: 18, tint: pres.ui.tint)
        headerItem.attributedTitle = headerText(pres: pres, config: config, state: state)

        // Mode checkmarks.
        for (mode, item) in modeItems {
            item.state = (config.mode == mode) ? .on : .off
        }

        // Timed session UI.
        let timedActive = config.timedUntil > Date().timeIntervalSince1970
        stopTimedItem.isHidden = !timedActive
    }

    // MARK: - Icon + header rendering

    private func applyIcon(_ ui: LumenUIState) {
        if let image = NSImage(systemSymbolName: ui.symbol, accessibilityDescription: "Lumen") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = "L"
        }
    }

    /// A configured SF Symbol image, optionally tinted with a palette colour.
    private func symbolImage(_ name: String, pointSize: CGFloat, tint: NSColor? = nil) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        if let tint {
            config = config.applying(.init(paletteColors: [tint]))
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = (tint == nil)
        return image
    }

    /// Builds the multi-line attributed title for the header row.
    private func headerText(pres: StatePresentation,
                            config: LumenConfig,
                            state: DaemonState?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titlePara = NSMutableParagraphStyle()
        titlePara.lineSpacing = 2
        titlePara.paragraphSpacing = 3

        result.append(NSAttributedString(string: pres.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titlePara,
        ]))

        let secondary: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: titlePara,
        ]

        result.append(NSAttributedString(string: "\n" + pres.reason, attributes: secondary))

        if let facts = factsLine(config: config, state: state), !facts.isEmpty {
            result.append(NSAttributedString(string: "\n" + facts, attributes: secondary))
        }
        return result
    }

    /// Compact facts line: power · battery · thermal · session.
    private func factsLine(config: LumenConfig, state: DaemonState?) -> String? {
        guard let state, StatePresentation.isFresh(state) else { return nil }
        var parts: [String] = []

        // Power source (+ battery percentage when available).
        if let pct = state.batteryPercent {
            let source = state.onBattery ? loc.string("value.onBattery") : loc.string("value.onAC")
            parts.append("\(source) \(pct)%")
        } else {
            parts.append(state.onBattery ? loc.string("value.onBattery") : loc.string("value.onAC"))
        }

        // Thermal (only worth showing when not nominal).
        if state.thermal != "nominal" {
            parts.append(StatePresentation.thermalLabel(state.thermal, loc: loc))
        }

        // Agent session detected?
        let detected = state.sessionActive || state.processActive
        parts.append(loc.string("label.session") + ": " +
                     loc.string(detected ? "value.yes" : "value.no"))

        return parts.joined(separator: "  ·  ")
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
