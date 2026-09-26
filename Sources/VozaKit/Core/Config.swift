import Foundation

/// User configuration. TOML-inspired simple `key = "value"` format at
/// ~/.config/voza/config.toml, plus optional .env for cloud cleanup keys
/// (D032: cleanup is cloud-only, explicit opt-in — local providers removed).
/// Every value is optional; defaults fit Jero's machine and degrade gracefully.
final class Config {
    static let shared = Config()

    // MARK: - Defaults / constants

    static let targetSampleRate: Double = 16_000
    static let transcriptionTimeoutSeconds: TimeInterval = 120

    /// V12 — credential keys live in the Keychain (then .env, then process
    /// env). CLEANUP_MODEL is provider config, not a secret: it stays
    /// file/shell-only.
    static let credentialKeys = ["OPENAI_API_KEY", "OPENAI_BASE_URL", "ANTHROPIC_API_KEY"]

    /// Back-compat read-only anchor for callers not yet migrated to injected
    /// paths (V02 owns that migration). Never creates directories: the
    /// side effect moved to `AppPaths` write-path preparation (plan-glm V01).
    static var appSupportDirectory: String { AppPaths.default.appSupport.path }

    // MARK: - Stored config values

    var modelId: String?
    var whisperBinary: String?
    var modelsDirectory: String?
    var logDirectory: String?
    var cleanupMode: String      // cloud | plain (D032: local modes removed)
    var language: String         // auto | en | es
    var playSound: Bool
    /// Wispr-style auto-learn (owner decision 2026-09-08): after each paste,
    /// watch ONLY the pasted element briefly to catch typed corrections.
    /// On by default — zero-effort learning is the product decision; the
    /// Settings toggle turns it off for users who prefer manual-only.
    var autoLearn: Bool
    var gumroadPermalink: String

    private(set) var env: [String: String] = [:]
    /// Only the .env-file layer (V12): the migration verifies the Keychain
    /// value against WHAT THE FILE SAYS before stripping any line.
    private(set) var envFileValues: [String: String] = [:]
    private var raw: [String: String] = [:]

    /// Injected dependencies (plan-glm V01). Defaults reproduce the exact
    /// baseline production layout; tests inject a QA environment so nothing
    /// outside it is read or written. No clock injected: Config performs no
    /// time operations today (dead dependency omitted on purpose).
    /// V12: `keychain` sits IN FRONT of the .env file — layered precedence
    /// Keychain → file → process env. The default production keychain store
    /// is namespaced per AppPaths so QA and production never share items;
    /// `nil` (tests/previews) disables the layer entirely, which keeps the
    /// whole existing suite hermetic: no QA test touches a keychain.
    private let paths: AppPaths
    private let keychain: KeychainStore?
    /// The adopted production store, set at launch (V12). `shared` starts
    /// with nil so a misordered launch would fail visibly (no provider)
    /// rather than silently skipping the Keychain layer.
    private var keychainStore: KeychainStore?

    init(paths: AppPaths = .default, keychain: KeychainStore? = nil) {
        self.paths = paths
        self.keychain = keychain
        // D032: default is "plain" — raw dictation needs zero decisions and
        // never touches the network. "cloud" is an explicit opt-in.
        cleanupMode = "plain"
        language = "auto"
        playSound = false
        autoLearn = true
        gumroadPermalink = "voza"
        load()
    }

    func reload() { load() }

    private func load() {
        raw = [:]
        let path = paths.configFile.path
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("[") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                raw[key] = value
            }
        }
        modelId        = raw["model"]
        whisperBinary  = raw["whisper_binary"]
        modelsDirectory = raw["models_dir"]
        logDirectory   = raw["log_dir"]
        // P2-2 (audit 2026-09-21): persisted but never loaded — the value only
        // survived until the next relaunch.
        gumroadPermalink = raw["gumroad_permalink"] ?? gumroadPermalink
        // D032 migration: legacy local values ("auto"/"ollama"/"mlx") map to
        // "plain" — local inference no longer exists. "cloud" is honored; an
        // explicit "plain" stays "plain".
        switch raw["cleanup"] {
        case "cloud": cleanupMode = "cloud"
        default:      cleanupMode = "plain"
        }
        language       = raw["language"] ?? "auto"
        playSound      = (raw["play_sound"] ?? "false") == "true"
        autoLearn      = (raw["auto_learn"] ?? "true") == "true"
        env = [:]
        envFileValues = [:]
        // V12 credential precedence, most-trusted first:
        //   1. Keychain (production; nil in tests/previews → layer absent)
        //   2. ~/.config/voza/.env file
        //   3. Process environment (shell) — can only ADD, never override
        //      the file (previously-pinned P2-e contract).
        // The keychain layer is read-only here: writes go through
        // `saveCleanupKey`/`deleteCleanupKey` so a migration can verify the
        // write before its file line is removed (V12-AC03).
        if let keychain = keychainStore ?? keychain {
            for key in Self.credentialKeys {
                if let v = keychain.get(key), !v.isEmpty { env[key] = v }
            }
        }
        let envPath = paths.envFile.path
        if let text = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                envFileValues[key] = value
                if env[key] == nil { env[key] = value }
            }
        }
        // Also read real process env as fallback.
        for key in Self.credentialKeys + ["CLEANUP_MODEL"] {
            if let v = ProcessInfo.processInfo.environment[key], env[key] == nil { env[key] = v }
        }
    }

    /// P0-1 (audit 2026-09-21): a provider exists ONLY when the user actually
    /// configured a key in .env (or the process env). The UI shows the cloud
    /// option only in that case, and the pipeline runs cleanup only in that
    /// case — the feature can never promise what it cannot do (the audit's
    /// "broken promise": mode cloud without a key silently pasted raw).
    var hasCleanupProvider: Bool {
        ["OPENAI_API_KEY", "ANTHROPIC_API_KEY"].contains { !env[$0, default: ""].isEmpty }
    }

    /// V12 — the production keychain. The service is the stable constant for
    /// the default config dir; any other (QA/custom) config dir gets a
    /// namespaced service derived from its PATH (stable across launches, so
    /// items stay readable) — a QA tree can never read production items.
    static func productionKeychain(for paths: AppPaths) -> KeychainStore {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent(".config/voza", isDirectory: true)
            .standardizedFileURL.path
        let dir = paths.appSupport.standardizedFileURL.path
        if dir == defaultDir {
            return SecItemKeychainStore(service: "com.jerotherey.voza.credentials")
        }
        return SecItemKeychainStore(service: "com.jerotherey.voza.credentials.dir-\(dir)")
    }

    /// Stores a cleanup credential in the Keychain and reloads the layered
    /// env. Returns false when the Keychain refused the write — the .env
    /// file (if any) stays untouched, so nothing is half-migrated (V12-AC03).
    @discardableResult
    func saveCleanupKey(_ key: String, value: String, keychain: KeychainStore) -> Bool {
        guard Self.credentialKeys.contains(key) else { return false }
        guard keychain.set(key, value: value) else { return false }
        reload()
        return true
    }

    /// V12 migration, one key at a time: strip the plaintext .env line ONLY
    /// after the Keychain read-back confirms the exact same value is durably
    /// stored. Order matters — verify first, delete second.
    @discardableResult
    func migrateEnvKeyToKeychain(_ key: String, keychain: KeychainStore) -> Bool {
        guard Self.credentialKeys.contains(key),
              let stored = keychain.get(key), !stored.isEmpty,
              let fileValue = envFileValues[key], fileValue == stored else { return false }
        removeEnvFileLines(forKey: key)
        reload()
        return true
    }

    /// Removes a credential everywhere (Keychain + file layers). Used by
    /// tests and, later, by the Settings “remove key” action.
    @discardableResult
    func deleteCleanupKey(_ key: String, keychain: KeychainStore) -> Bool {
        guard Self.credentialKeys.contains(key) else { return false }
        let ok = keychain.delete(key)
        removeEnvFileLines(forKey: key)
        reload()
        return ok
    }

    private func removeEnvFileLines(forKey key: String) {
        let path = paths.envFile.path
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let kept = text.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return true }
            let k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
            return k != key
        }
        guard paths.prepareAppSupport() else { return }
        try? kept.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - V12 production adoption

    /// Called ONCE at app launch, before anything reads `Config.shared.env`:
    /// adopts the real (SecItem) keychain and, for users upgrading with a
    /// plaintext .env, moves each key into the Keychain and strips ONLY the
    /// lines whose values were verified stored. The file keeps comments and
    /// non-credential entries; a failed Keychain write leaves the file as-is
    /// (nothing half-migrated).
    static func adoptProductionKeychain() {
        let paths = AppPaths.default
        let keychain = productionKeychain(for: paths)
        shared.keychainStore = keychain
        shared.reload()
        for key in credentialKeys where shared.envFileValues[key] != nil {
            // Keychain may already hold the value from a previous run — the
            // migration's verify-then-strip handles both cases.
            if keychain.get(key) == nil, let value = shared.envFileValues[key] {
                guard keychain.set(key, value: value) else { continue }
            }
            shared.migrateEnvKeyToKeychain(key, keychain: keychain)
        }
    }

    // MARK: - Explicit setters (persist to config.toml)

    func setModel(_ v: String?)            { modelId = v;        if let v { raw["model"] = v }; persist() }
    func setWhisperBinary(_ v: String?)    { whisperBinary = v;  if let v { raw["whisper_binary"] = v }; persist() }
    func setModelsDirectory(_ v: String?)  { modelsDirectory = v; if let v { raw["models_dir"] = v }; persist() }
    /// D032: only two modes exist. "plain" (default) never touches the
    /// network; "cloud" is the explicit opt-in. Anything else is clamped to
    /// plain — the privacy invariant (no net without explicit consent) is
    /// enforced at the setter, not just the reader.
    func setCleanupMode(_ v: String) {
        let clamped = (v == "cloud") ? "cloud" : "plain"
        cleanupMode = clamped
        raw["cleanup"] = clamped
        persist()
    }
    func setLanguage(_ v: String)          { language = v;       raw["language"] = v; persist() }
    func setPlaySound(_ v: Bool)           { playSound = v;      raw["play_sound"] = v ? "true" : "false"; persist() }
    func setAutoLearn(_ v: Bool)           { autoLearn = v;      raw["auto_learn"] = v ? "true" : "false"; persist() }

    private func persist() {
        var lines = ["# Voza configuration — edited from the app or by hand."]
        if let v = modelId {          lines.append("model = \"\(v)\"") }
        if let v = whisperBinary {    lines.append("whisper_binary = \"\(v)\"") }
        if let v = modelsDirectory {  lines.append("models_dir = \"\(v)\"") }
        if let v = logDirectory {     lines.append("log_dir = \"\(v)\"") }
        lines.append("cleanup = \"\(cleanupMode)\"")
        lines.append("language = \"\(language)\"")
        lines.append("play_sound = \(playSound ? "true" : "false")")
        lines.append("auto_learn = \(autoLearn ? "true" : "false")")
        lines.append("gumroad_permalink = \"\(gumroadPermalink)\"")
        let text = lines.joined(separator: "\n") + "\n"
        // Write path: prepare the tree right before persisting (reads never create).
        guard paths.prepareAppSupport() else { return }
        try? text.write(toFile: paths.configFile.path, atomically: true, encoding: .utf8)
    }

    // MARK: - Resolved values

    var resolvedModelId: String { modelId ?? HardwareProfile.recommendedModel(language: resolvedLanguage) }
    var resolvedCleanupMode: String { cleanupMode }
    /// "auto" means the SPEECH language is auto-detected by the engine (whisper.cpp -l auto).
    /// It must never be inferred from the UI language — a Spanish speaker with an English UI
    /// still gets auto-detection (P0 fix from external audit v2, §3.1).
    var resolvedLanguage: String {
        switch language {
        case "en", "es": return language
        default: return "auto"
        }
    }
    var resolvedModelsDirectory: String {
        modelsDirectory ?? paths.models.path
    }
    var resolvedLogDirectory: String {
        logDirectory ?? paths.history.path
    }
    var resolvedWhisperBinary: String { whisperBinary ?? "/opt/homebrew/bin/whisper-cli" }
}
