import Foundation

/// Very small strings loader backed by `shared/i18n/{en,ru,kk}.json`.
///
/// It defaults to English and follows the system language unless the config
/// pins a specific language. Missing keys fall back to English, then to the
/// key itself, so the UI never shows a blank label.
public final class Localizer: @unchecked Sendable {

    public static let supported = ["en", "ru", "kk"]

    private var table: [String: String] = [:]
    private var fallback: [String: String] = [:]
    public private(set) var language: String

    /// - Parameters:
    ///   - resourcesDir: directory containing `i18n/<lang>.json` (the app's
    ///     `Contents/Resources`). If nil, only key-fallback works.
    ///   - preferred: "system" or one of the supported codes.
    public init(resourcesDir: String?, preferred: String = "system") {
        let lang = Localizer.resolveLanguage(preferred)
        self.language = lang
        guard let dir = resourcesDir else { return }
        self.fallback = Localizer.loadTable(dir: dir, lang: "en")
        self.table = (lang == "en") ? fallback : Localizer.loadTable(dir: dir, lang: lang)
    }

    public func string(_ key: String) -> String {
        table[key] ?? fallback[key] ?? key
    }

    /// Convenience for a formatted string with positional `%@`-style args
    /// resolved by the caller (kept simple on purpose).
    public func string(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }

    // MARK: - Resolution

    static func resolveLanguage(_ preferred: String) -> String {
        if preferred != "system", supported.contains(preferred) {
            return preferred
        }
        // Follow the system's preferred languages, first supported match wins.
        for pref in Locale.preferredLanguages {
            let code = String(pref.prefix(2)).lowercased()
            if supported.contains(code) { return code }
        }
        return "en"
    }

    private static func loadTable(dir: String, lang: String) -> [String: String] {
        let path = "\(dir)/i18n/\(lang).json"
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }
}
