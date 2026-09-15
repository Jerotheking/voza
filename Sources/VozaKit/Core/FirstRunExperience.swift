import Foundation

/// One-shot flag for the first-dictation teaching moment. After the first
/// successful paste, the app shows a short panel that teaches the two habits
/// that make Voza stick: the hotkey ("hold an Option key") and auto-learn
/// ("fix it by typing — Voza learns"). Shown exactly once per install; the
/// moment is placed right AFTER the first paste because that's when the
/// muscle memory is forming, not during setup where it would be forgotten.
///
/// Isolation follows the V01/V02 injection pattern: tests point
/// `defaultsSuite` at a volatile suite, so the real user preference domain is
/// never touched from a test process.
enum FirstRunExperience {
    private static let key = "voza.firstDictationCelebrated"

    /// Injection seam (matt-tdd): production reads UserDefaults.standard;
    /// tests inject an ephemeral volatile suite.
    static var defaultsSuite: UserDefaults?

    private static var defaults: UserDefaults { defaultsSuite ?? .standard }

    /// True until the first-dictation moment has been shown (flag absent).
    static var firstDictationPending: Bool {
        defaults.object(forKey: key) == nil
    }

    /// Consumes the one-shot. Idempotent; safe to call even if the panel
    /// failed to display (a missed celebration is better than a repeated one).
    static func markFirstDictationShown() {
        defaults.set(true, forKey: key)
    }
}
