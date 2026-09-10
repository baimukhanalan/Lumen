import AppKit
import SwiftUI
import LumenCore

/// Hosts the SwiftUI `SettingsView` inside a standard `NSWindow` via
/// `NSHostingController`. A single window instance is reused and re-fronted.
@available(macOS 12.0, *)
final class SettingsWindowController: NSWindowController {

    private let model = ConfigModel()
    private let loc: Localizer

    init(loc: Localizer) {
        self.loc = loc

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = loc.string("window.settings")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        rebuildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuild the hosted view so it reflects the current install state.
    private func rebuildContent() {
        model.reload()
        let root = SettingsView(
            model: model,
            loc: loc,
            onInstall: { [weak self] in self?.install() },
            onUninstall: { [weak self] in self?.uninstall() },
            daemonInstalled: PrivilegedInstaller.isInstalled
        )
        window?.contentViewController = NSHostingController(rootView: root)
    }

    func show() {
        rebuildContent()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
            presentInfo(loc.string(successKey))
        case .cancelled:
            break // user dismissed the auth dialog; nothing to say
        case .failure(let message):
            presentInfo(loc.string("alert.failed") + "\n\n" + message)
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
