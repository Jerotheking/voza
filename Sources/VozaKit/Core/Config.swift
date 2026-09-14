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
    /// Ollama keep_alive (D023): how long the cleanup model stays resident in
    /// RAM after a request. Default "5m" — a dictation cleaner must never be a
    /// permanent RAM tenant (owner saw 6.8 GB RSS with qwen3:8b resident).
    var ollamaKeepAlive: String
    var language: String         // auto | en | es
    var playSound: Bool
    /// Wispr-style auto-learn (owner decision 2026-09-08): after each paste,
    /// watch ONLY the pasted element briefly to catch typed corrections.
    /// On by default — zero-effort learning is the product decision; the
    /// Settings toggle turns it off for users who prefer manual-only.
    var autoLearn: Bool
    /// D026 — preload Pulido weights at launch (TypeWhisper-style warm start).
    var mlxPreload: Bool
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
        // D023 (measured 2026-09-10): qwen3 is a thinking model — even with the
        // no-think soft-switch it burned 1024 tokens before any output (16 s
        // cleanups). gemma3 has no thinking phase: 30 tokens, 0.5 s warm.
        ollamaModel = "gemma3:4b"
        ollamaKeepAlive = "5m"
        language = "auto"
        playSound = false
        autoLearn = true
        mlxPreload = true
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
        ollamaModel    = raw["ollama_model"] ?? "gemma3:4b"
        ollamaKeepAlive = raw["ollama_keep_alive"] ?? "5m"
        language       = raw["language"] ?? "auto"
        playSound      = (raw["play_sound"] ?? "false") == "true"
        autoLearn      = (raw["auto_learn"] ?? "true") == "true"
        mlxPreload     = (raw["mlx_preload"] ?? "true") == "true"

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
    func setOllamaKeepAlive(_ v: String)   { ollamaKeepAlive = v; raw["ollama_keep_alive"] = v; persist() }
    /// Test seam: inject a synthetic env entry without touching process env.
    func setenvOverride(_ key: String, _ value: String) { env[key] = value }
    func setLanguage(_ v: String)          { language = v;       raw["language"] = v; persist() }
    func setPlaySound(_ v: Bool)           { playSound = v;      raw["play_sound"] = v ? "true" : "false"; persist() }
    func setAutoLearn(_ v: Bool)           { autoLearn = v;      raw["auto_learn"] = v ? "true" : "false"; persist() }
    func setMlxPreload(_ v: Bool)          { mlxPreload = v;     raw["mlx_preload"] = v ? "true" : "false"; persist() }
    func setGumroadPermalink(_ v: String)  { gumroadPermalink = v; raw["gumroad_permalink"] = v; persist() }

    private func persist() {
        var lines = ["# Voza configuration — edited from the app or by hand."]
        if let v = modelId {          lines.append("model = \"\(v)\"") }
        if let v = whisperBinary {    lines.append("whisper_binary = \"\(v)\"") }
        if let v = modelsDirectory {  lines.append("models_dir = \"\(v)\"") }
        if let v = logDirectory {     lines.append("log_dir = \"\(v)\"") }
        lines.append("cleanup = \"\(cleanupMode)\"")
        lines.append("ollama_model = \"\(ollamaModel)\"")
        lines.append("ollama_keep_alive = \"\(ollamaKeepAlive)\"")
        lines.append("language = \"\(language)\"")
        lines.append("play_sound = \(playSound ? "true" : "false")")
        lines.append("auto_learn = \(autoLearn ? "true" : "false")")
        lines.append("mlx_preload = \(mlxPreload ? "true" : "false")")
        lines.append("gumroad_permalink = \"\(gumroadPermalink)\"")
        let text = lines.joined(separator: "\n") + "\n"
        // Write path: prepare the tree right before persisting (reads never create).
        guard paths.prepareAppSupport() else { return }
        try? text.write(toFile: paths.configFile.path, atomically: true, encoding: .utf8)
    }

    // MARK: - Resolved values

    var resolvedModelId: String { modelId ?? HardwareProfile.recommendedModel(language: resolvedLanguage) }
    var resolvedOllamaModel: String { env["OLLAMA_MODEL"] ?? ollamaModel }
    var resolvedOllamaKeepAlive: String { env["OLLAMA_KEEP_ALIVE"] ?? ollamaKeepAlive }
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
