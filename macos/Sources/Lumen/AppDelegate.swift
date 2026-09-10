import AppKit
import LumenCore

/// Coordinates the menu-bar controller, settings window, and first-run install.
@available(macOS 12.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Cross-process signal (from a second launch) asking us to open Settings.
    static let openSettingsNotification = Notification.Name("com.lumen.openSettings")

    private var l10n: L10n!
    private var statusController: StatusItemController!
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Resolve localization from config's language preference.
        let paths = Paths.forCurrentUser()
        // A genuine first launch is one with no config file yet — capture that
        // *before* ensureExists writes the defaults.
        let firstRun = !FileManager.default.fileExists(atPath: paths.configFile)
        ConfigStore.ensureExists(at: paths.configFile)
        let config = ConfigStore.load(at: paths.configFile)
        let resources = Bundle.main.resourcePath
        // Reactive localization manager: initialized in the configured language
        // so the app launches correctly localized, then re-publishes live when
        // the language is changed from Settings.
        l10n = L10n(resourcesDir: resources, preferred: config.language)

        statusController = StatusItemController(
            loc: l10n,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onInstall: { [weak self] in self?.installIfNeeded(force: true) }
        )

        // Listen for a second launch asking us to show Settings.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenSettingsNotification),
            name: AppDelegate.openSettingsNotification,
            object: nil
        )

        // Offer to install the daemon on first run.
        installIfNeeded(force: false)

        // On a genuine first launch, always show Settings once so the user sees
        // the app "open" — otherwise a menu-bar-only app looks like nothing
        // happened.
        if firstRun {
            showSettings()
        }
    }

    // MARK: - Reopen / activation

    /// Double-clicking the app (or `open -a Lumen`) when it is already running
    /// re-shows the Settings window and brings the app forward.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func handleOpenSettingsNotification() {
        // Distributed notifications arrive on the main thread here, but hop
        // explicitly to be safe about UI work.
        DispatchQueue.main.async { [weak self] in self?.showSettings() }
    }

    // MARK: - Settings

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(l10n: l10n)
        }
        settingsWindow?.show()
    }

    /// Prompt-and-install. `force == false` is the first-run path (skips if
    /// already installed); `force == true` reinstalls on demand.
    private func installIfNeeded(force: Bool) {
        if PrivilegedInstaller.isInstalled && !force { return }

        let alert = NSAlert()
        alert.messageText = "Lumen"
        alert.informativeText = PrivilegedInstaller.isInstalled
            ? l10n.t("install.reinstallPrompt")
            : l10n.t("install.firstRunPrompt")
        alert.addButton(withTitle: l10n.t("install.install"))
        alert.addButton(withTitle: l10n.t("install.later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let result = PrivilegedInstaller.installOrUpdate()
        switch result {
        case .success:
            info(l10n.t("alert.installed"))
        case .cancelled:
            break
        case .failure(let message):
            info(l10n.t("alert.failed") + "\n\n" + message)
        }
    }

    private func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Lumen"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
