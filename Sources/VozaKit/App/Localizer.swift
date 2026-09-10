import Foundation

/// Bilingual string helper. Picks Spanish when the system (or the Voza override)
/// prefers it; English otherwise. Inline at call sites: L.t("Hello", es: "Hola").
enum L {
    /// Injectable defaults for tests (V02): nil = production standard domain.
    static var defaultsSuite: UserDefaults?

    static var override: String? {
        get { (defaultsSuite ?? .standard).string(forKey: "voza.language") }
        set { (defaultsSuite ?? .standard).set(newValue, forKey: "voza.language") }
    }

    static var isSpanish: Bool {
        resolveIsSpanish(override: override,
                         systemLanguages: (defaultsSuite ?? .standard).stringArray(forKey: "AppleLanguages"))
    }

    /// Pure resolution rule (V02): override wins; otherwise the primary system
    /// language decides. Injectable so tests never touch global preferences —
    /// reading `AppleLanguages` from tests mutated real user defaults.
    static func resolveIsSpanish(override: String?, systemLanguages: [String]?) -> Bool {
        if let o = override { return o == "es" }
        return systemLanguages?.first?.hasPrefix("es") == true
    }

    /// Pure string resolution counterpart of `t` (V02).
    static func resolve(_ en: String, es: String, spanish: Bool) -> String {
        spanish ? es : en
    }

    static func t(_ en: String, es: String) -> String {
        resolve(en, es: es, spanish: isSpanish)
    }
}
