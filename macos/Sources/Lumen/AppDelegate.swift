import AppKit
import LumenCore

/// Coordinates the menu-bar controller, settings window, and first-run install.
@available(macOS 12.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var localizer: Localizer!
    private var statusController: StatusItemController!
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Resolve localization from config's language preference.
        let paths = Paths.forCurrentUser()
        ConfigStore.ensureExists(at: paths.configFile)
        let config = ConfigStore.load(at: paths.configFile)
        let resources = Bundle.main.resourcePath
        localizer = Localizer(resourcesDir: resources, preferred: config.language)

        statusController = StatusItemController(
            loc: localizer,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onInstall: { [weak self] in self?.installIfNeeded(force: true) }
        )

        // Offer to install the daemon on first run.
        installIfNeeded(force: false)
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(loc: localizer)
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
            ? localizer.string("install.reinstallPrompt")
            : localizer.string("install.firstRunPrompt")
        alert.addButton(withTitle: localizer.string("install.install"))
        alert.addButton(withTitle: localizer.string("install.later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let result = PrivilegedInstaller.installOrUpdate()
        switch result {
        case .success:
            info(localizer.string("alert.installed"))
        case .cancelled:
            break
        case .failure(let message):
            info(localizer.string("alert.failed") + "\n\n" + message)
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
