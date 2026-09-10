import Foundation
import Combine
import LumenCore

/// Reactive localization manager for the app target.
///
/// Unlike the value-type `Localizer` in LumenCore (used by the daemon), this is
/// an `ObservableObject`: changing the language reloads the string table from
/// the app bundle's `Resources/i18n/<lang>.json` and publishes the change so
/// every SwiftUI view that observes it re-renders instantly — no relaunch.
///
/// AppKit surfaces (the menu-bar menu, the window title) can't observe an
/// `ObservableObject` directly, so a change also broadcasts `L10n.didChange`
/// via `NotificationCenter` for them to rebuild.
@available(macOS 12.0, *)
final class L10n: ObservableObject {

    /// Posted (on the main thread) whenever the active language changes.
    static let didChange = Notification.Name("com.lumen.languageChanged")

    /// The resolved language code actually in effect ("en" | "ru" | "kk").
    /// This is the resolution of the *preferred* value (which may be "system").
    @Published private(set) var language: String

    private var table: [String: String] = [:]
    private var fallback: [String: String] = [:]
    private let resourcesDir: String?

    /// - Parameters:
    ///   - resourcesDir: directory containing `i18n/<lang>.json` (the app's
    ///     `Contents/Resources`). If nil, only key-fallback works.
    ///   - preferred: "system" or one of the supported codes.
    init(resourcesDir: String?, preferred: String = "system") {
        self.resourcesDir = resourcesDir
        let lang = Localizer.resolveLanguage(preferred)
        self.language = lang
        loadTables(for: lang)
    }

    /// Switch to `preferred` ("system" | "en" | "ru" | "kk"), reloading the
    /// table and publishing the change. Always reloads — re-selecting "system"
    /// re-resolves against the current system languages.
    func setLanguage(_ preferred: String) {
        let lang = Localizer.resolveLanguage(preferred)
        loadTables(for: lang)
        language = lang // @Published — re-renders every observing SwiftUI view
        NotificationCenter.default.post(name: L10n.didChange, object: self)
    }

    /// Look up a localized string, falling back to English then the key itself.
    func t(_ key: String) -> String {
        table[key] ?? fallback[key] ?? key
    }

    /// Formatted overload with positional `%@`/`%d`-style args.
    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - Table loading

    private func loadTables(for lang: String) {
        guard let dir = resourcesDir else {
            table = [:]; fallback = [:]; return
        }
        fallback = L10n.loadTable(dir: dir, lang: "en")
        table = (lang == "en") ? fallback : L10n.loadTable(dir: dir, lang: lang)
    }

    private static func loadTable(dir: String, lang: String) -> [String: String] {
        let path = "\(dir)/i18n/\(lang).json"
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }
}
