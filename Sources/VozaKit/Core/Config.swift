import Foundation

/// User configuration. TOML-inspired simple `key = "value"` format at
/// ~/.config/voza/config.toml, plus optional .env for cloud cleanup keys.
/// Every value is optional; defaults fit Jero's machine and degrade gracefully.
final class Config {
    static let shared = Config()

    // MARK: - Defaults / constants

    static let targetSampleRate: Double = 16_000
    static let transcriptionTimeoutSeconds: TimeInterval = 120

    /// Back-compat read-only anchor for callers not yet migrated to injected
    /// paths (V02 owns that migration). Never creates directories: the
    /// side effect moved to `AppPaths` write-path preparation (plan-glm V01).
    static var appSupportDirectory: String { AppPaths.default.appSupport.path }

    // MARK: - Stored config values

    var modelId: String?
    var whisperBinary: String?
    var modelsDirectory: String?
    var logDirectory: String?
    var cleanupMode: String      // auto | ollama | cloud | plain
    var ollamaModel: String
    var language: String         // auto | en | es
    var playSound: Bool
    var gumroadPermalink: String

    private(set) var env: [String: String] = [:]
    private var raw: [String: String] = [:]

    /// Injected dependencies (plan-glm V01). Defaults reproduce the exact
    /// baseline production layout; tests inject a QA environment so nothing
    /// outside it is read or written. No clock injected: Config performs no
    /// time operations today (dead dependency omitted on purpose).
    private let paths: AppPaths

    init(paths: AppPaths = .default) {
        self.paths = paths
        cleanupMode = "auto"
        ollamaModel = "qwen3:8b"
        language = "auto"
        playSound = false
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
        cleanupMode    = raw["cleanup"] ?? "auto"
        ollamaModel    = raw["ollama_model"] ?? "qwen3:8b"
        language       = raw["language"] ?? "auto"
        playSound      = (raw["play_sound"] ?? "false") == "true"

        env = [:]
        let envPath = paths.envFile.path
        if let text = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                env[key] = value
            }
        }
        // Also read real process env as fallback.
        for key in ["OPENAI_API_KEY", "OPENAI_BASE_URL", "ANTHROPIC_API_KEY", "CLEANUP_MODEL", "OLLAMA_MODEL"] {
            if let v = ProcessInfo.processInfo.environment[key], env[key] == nil { env[key] = v }
        }
    }

    // MARK: - Explicit setters (persist to config.toml)

    func setModel(_ v: String?)            { modelId = v;        if let v { raw["model"] = v }; persist() }
    func setWhisperBinary(_ v: String?)    { whisperBinary = v;  if let v { raw["whisper_binary"] = v }; persist() }
    func setModelsDirectory(_ v: String?)  { modelsDirectory = v; if let v { raw["models_dir"] = v }; persist() }
    func setLogDirectory(_ v: String?)     { logDirectory = v;   if let v { raw["log_dir"] = v }; persist() }
    func setCleanupMode(_ v: String)       { cleanupMode = v;    raw["cleanup"] = v; persist() }
    func setOllamaModel(_ v: String)       { ollamaModel = v;    raw["ollama_model"] = v; persist() }
    func setLanguage(_ v: String)          { language = v;       raw["language"] = v; persist() }
    func setPlaySound(_ v: Bool)           { playSound = v;      raw["play_sound"] = v ? "true" : "false"; persist() }
    func setGumroadPermalink(_ v: String)  { gumroadPermalink = v; raw["gumroad_permalink"] = v; persist() }

    private func persist() {
        var lines = ["# Voza configuration — edited from the app or by hand."]
        if let v = modelId {          lines.append("model = \"\(v)\"") }
        if let v = whisperBinary {    lines.append("whisper_binary = \"\(v)\"") }
        if let v = modelsDirectory {  lines.append("models_dir = \"\(v)\"") }
        if let v = logDirectory {     lines.append("log_dir = \"\(v)\"") }
        lines.append("cleanup = \"\(cleanupMode)\"")
        lines.append("ollama_model = \"\(ollamaModel)\"")
        lines.append("language = \"\(language)\"")
        lines.append("play_sound = \(playSound ? "true" : "false")")
        lines.append("gumroad_permalink = \"\(gumroadPermalink)\"")
        let text = lines.joined(separator: "\n") + "\n"
        // Write path: prepare the tree right before persisting (reads never create).
        guard paths.prepareAppSupport() else { return }
        try? text.write(toFile: paths.configFile.path, atomically: true, encoding: .utf8)
    }

    // MARK: - Resolved values

    var resolvedModelId: String { modelId ?? HardwareProfile.recommendedModel(language: resolvedLanguage) }
    var resolvedOllamaModel: String { env["OLLAMA_MODEL"] ?? ollamaModel }
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

    var ollamaDetected: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama", isDirectory: &isDir)
            || FileManager.default.fileExists(atPath: "/usr/local/bin/ollama", isDirectory: &isDir)
    }
}
