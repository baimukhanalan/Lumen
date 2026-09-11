import AppKit
import SwiftUI
import LumenCore

/// Hosts the SwiftUI `SettingsView` inside a standard `NSWindow` via
/// `NSHostingController`. A single window instance is reused and re-fronted.
///
/// Because the app runs as an `.accessory` (no Dock icon), we temporarily
/// promote it to `.regular` while the window is visible. That lets the window
/// become key/main and gives it a proper Dock presence and app menu; we drop
/// back to `.accessory` when it closes so the app stays menu-bar-only.
@available(macOS 12.0, *)
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let model = ConfigModel()
    private let l10n: L10n

    init(l10n: L10n) {
        self.l10n = l10n

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("window.settings")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        window.delegate = self
        rebuildContent()

        // Keep the window title in sync when the language switches live.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: L10n.didChange,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func languageChanged() {
        window?.title = l10n.t("window.settings")
    }

    /// Rebuild the hosted view so it reflects the current install state.
    private func rebuildContent() {
        model.reload()
        let root = SettingsView(
            model: model,
            l10n: l10n,
            onInstall: { [weak self] in self?.install() },
            onUninstall: { [weak self] in self?.uninstall() },
            daemonInstalled: PrivilegedInstaller.isInstalled
        )
        window?.contentViewController = NSHostingController(rootView: root)
        window?.title = l10n.t("window.settings")
    }

    func show() {
        rebuildContent()
        // Promote to a regular app so the accessory window can take focus and
        // sit in front like a normal Settings window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-only once the window is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Reflect any external changes (e.g. a mode picked from the menu bar)
        // that happened while the window was in the background.
        model.reload()
    }

    private func install() {
        let result = PrivilegedInstaller.installOrUpdate()
        report(result, successKey: "alert.installed")
        rebuildContent()
    }

    private func uninstall() {
        let result = PrivilegedInstaller.uninstall()
        report(result, successKey: "alert.uninstalled")
        rebuildContent()
    }

    private func report(_ result: PrivilegedInstaller.Result, successKey: String) {
        switch result {
        case .success:
            presentInfo(l10n.t(successKey))
        case .cancelled:
            break // user dismissed the auth dialog; nothing to say
        case .failure(let message):
            presentInfo(l10n.t("alert.failed") + "\n\n" + message)
        }
    }

    private func presentInfo(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Lumen"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
