import Foundation

/// Bilingual string helper. Picks Spanish when the system (or the Voza override)
/// prefers it; English otherwise. Inline at call sites: L.t("Hello", es: "Hola").
enum L {
    static var override: String? {
        get { UserDefaults.standard.string(forKey: "voza.language") }
        set { UserDefaults.standard.set(newValue, forKey: "voza.language") }
    }

    static var isSpanish: Bool {
        if let o = override { return o == "es" }
        let langs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
        return langs.first?.hasPrefix("es") == true
    }

    static func t(_ en: String, es: String) -> String {
        isSpanish ? es : en
    }
}
