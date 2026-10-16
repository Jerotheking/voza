import Foundation

/// D032 — AI cleanup of transcripts: punctuation, capitalization, filler
/// removal. CLOUD-ONLY, EXPLICIT OPT-IN.
///
/// PRIVACY POLICY (hardened per external audit v2, §3.8; D032 rewrite):
/// - "plain" (default) → no processing at all: raw transcript pasted.
/// - "cloud" → explicit user choice: OpenAI-compatible → Anthropic, keys
///   from the user's own ~/.config/voza/.env or Keychain. Only already-transcribed
///   text crosses to the cloud, never audio, never by default.
enum Cleaner {

    /// V18 / D065 — 1-click cloud provider presets so users never have to hunt
    /// for base URLs or model IDs manually.
    enum CloudProviderPreset: String, CaseIterable, Identifiable, Sendable {
        case groq
        case openai
        case anthropic
        case openrouter

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .groq:       return L.t("Groq Ultra-Fast (~180 ms · Llama 3.3 70B)", es: "Groq Ultra-Rápido (~180 ms · Llama 3.3 70B)")
            case .openai:     return "OpenAI (gpt-4o-mini)"
            case .anthropic:  return "Anthropic (Claude 3.5 Haiku)"
            case .openrouter: return "OpenRouter (Gemini 2.5 Flash)"
            }
        }

        var baseURL: String? {
            switch self {
            case .groq:       return "https://api.groq.com/openai/v1"
            case .openrouter: return "https://openrouter.ai/api/v1"
            case .openai, .anthropic: return nil
            }
        }

        var defaultModel: String {
            switch self {
            case .groq:       return "llama-3.3-70b-versatile"
            case .openai:     return "gpt-4o-mini"
            case .anthropic:  return "claude-3-5-haiku-latest"
            case .openrouter: return "google/gemini-2.5-flash"
            }
        }

        var keySlot: String {
            switch self {
            case .anthropic: return "ANTHROPIC_API_KEY"
            case .groq, .openai, .openrouter: return "OPENAI_API_KEY"
            }
        }

        var keyPlaceholder: String {
            switch self {
            case .groq:       return "gsk_…"
            case .openai:     return "sk-…"
            case .anthropic:  return "sk-ant-…"
            case .openrouter: return "sk-or-…"
            }
        }

        /// Detects the active preset from current environment/config values, or
        /// from a pasted API key prefix (`gsk_`, `sk-ant-`, `sk-or-`).
        static func detect(fromKey rawKey: String) -> CloudProviderPreset? {
            let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("gsk_") { return .groq }
            if trimmed.hasPrefix("sk-ant-") { return .anthropic }
            if trimmed.hasPrefix("sk-or-") { return .openrouter }
            if trimmed.hasPrefix("sk-") { return .openai }
            return nil
        }

        static func current(in env: [String: String]) -> CloudProviderPreset {
            let base = env["OPENAI_BASE_URL"]?.lowercased() ?? ""
            if base.contains("groq.com") { return .groq }
            if base.contains("openrouter.ai") { return .openrouter }
            if !(env["ANTHROPIC_API_KEY"] ?? "").isEmpty && (env["OPENAI_API_KEY"] ?? "").isEmpty {
                return .anthropic
            }
            return .groq
        }
    }

    /// What actually happened during cleanup. `applied` is true only when a
    /// provider really transformed the text — history/UI must never claim a
    /// cleaning that did not occur (audit v2 §1.2-5, §3.9).
    struct CleaningOutcome: Sendable {
        let text: String
        let applied: Bool
        let provider: String?   // "openai" | "anthropic" | nil
    }

    /// The exact provider chain for a mode — pure, so tests can prove the
    /// privacy boundary: no mode ever contains a local provider (they are
    /// gone per D032) and ONLY the explicit "cloud" mode reaches the net.
    static func providerChain(for mode: String) -> [String] {
        switch mode {
        case "cloud":   return ["openai", "anthropic"]
        default:        return []                    // "plain" — passthrough
        }
    }

    /// `transport` is the V12 boundary seam: production uses the hardened
    /// SecureCleanupTransport (HTTPS-only/loopback, redirects cancelled);
    /// tests inject a transport over a stub URLProtocol to prove the
    /// privacy/redirect contracts without sockets.
    static func clean(_ text: String, config: Config,
                      bundleIdentifier: String? = nil,
                      transport: SecureCleanupTransport = SecureCleanupTransport()) async -> CleaningOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.resolvedCleanupMode == "cloud",
              !trimmed.isEmpty else { return CleaningOutcome(text: text, applied: false, provider: nil) }

        let deadline = Date().addingTimeInterval(30)
        for provider in providerChain(for: config.resolvedCleanupMode) {
            guard !Task.isCancelled, Date() < deadline else { break }
            let result: String?
            switch provider {
            case "openai":
                result = await openAIClean(trimmed, config: config, bundleIdentifier: bundleIdentifier, transport: transport)
            case "anthropic":
                result = await anthropicClean(trimmed, config: config, bundleIdentifier: bundleIdentifier, transport: transport)
            default:
                result = nil
            }
            if Task.isCancelled {
                return CleaningOutcome(text: text, applied: false, provider: nil)
            }
            if let cleanedText = result {
                return CleaningOutcome(text: cleanedText, applied: true, provider: provider)
            }
        }
        // Every provider in the chain failed → raw transcript, honestly reported.
        return CleaningOutcome(text: text, applied: false, provider: nil)
    }

    // MARK: - Prompt & App-Aware Context (D065)

    /// D023-era rule #3 (voice edit commands) stays: it is prompt-level, mode-
    /// independent, and cloud models honor it the same way the local one did.
    static let systemPrompt = """
    You clean dictated transcripts. Apply ONLY these transformations:
    1. Fix punctuation and capitalization — always capitalize the first word of the text and of each sentence.
    2. Remove filler words and stutters.
    3. EDIT COMMANDS: phrases like "quita lo de X", "quita eso", "borra lo último", "no, di mejor X" are spoken EDIT COMMANDS targeting the dictation itself — apply them (delete/rephrase the targeted part) and NEVER output the command itself.
    4. Keep the speaker's language, meaning and tone. Do not rewrite, translate or add anything.
    Output ONLY the cleaned text — no quotes, no commentary.
    """

    /// Pure mapping from the frontmost app's bundle identifier to a lightweight
    /// formatting hint (`D065`), avoiding manual "mode switching" while keeping
    /// the speaker's exact words and tone.
    static func appContextHint(forBundleIdentifier bundleId: String?) -> String? {
        guard let b = bundleId?.lowercased(), !b.isEmpty else { return nil }
        let codeBundles = [
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.microsoft.vscode",
            "com.apple.dt.xcode",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
            "com.mitchellh.ghostty",
            "dev.zed.zed",
        ]
        if codeBundles.contains(where: { b.contains($0) }) {
            return "ACTIVE APP CONTEXT: Developer IDE or Terminal. Preserve technical terms, CLI flags, function/variable names, and paths accurately."
        }
        let chatBundles = [
            "net.whatsapp.whatsapp",
            "com.tinyspeck.slackmacgap",
            "com.apple.mobilesms",
            "ru.keepcoder.telegram",
            "com.hnc.discord",
        ]
        if chatBundles.contains(where: { b.contains($0) }) {
            return "ACTIVE APP CONTEXT: Instant messaging / chat. Keep a natural, direct conversational tone without adding formal greetings or sign-offs."
        }
        let docBundles = [
            "com.apple.mail",
            "com.microsoft.outlook",
            "com.readdle.smartemail",
            "notion.id",
            "md.obsidian",
            "com.apple.notes",
        ]
        if docBundles.contains(where: { b.contains($0) }) {
            return "ACTIVE APP CONTEXT: Email or document editor. Format sentences and paragraph breaks cleanly while preserving the speaker's exact words."
        }
        return nil
    }

    static func systemPrompt(forBundleIdentifier bundleId: String?) -> String {
        guard let hint = appContextHint(forBundleIdentifier: bundleId) else {
            return systemPrompt
        }
        return systemPrompt + "\n" + hint
    }

    /// Safety net: some OpenAI-compatible proxies (OpenRouter) route to
    /// thinking models whose reasoning can leak into `message.content`.
    /// Measured live with qwen3: entire responses arrived as reasoning with
    /// empty answers. The paste must NEVER contain a think block.
    static func stripThinkingJunk(_ text: String) -> String {
        guard let start = text.range(of: "<think>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Unclosed block (truncated by num_predict): no answer exists after it —
        // the entire remainder is reasoning. Return empty → caller falls back
        // to the raw transcript instead of ever pasting reasoning.
        guard let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) else { return "" }
        let out = text.replacingCharacters(in: text.startIndex..<end.upperBound, with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cloud request contracts (pure, hermetically testable)

    /// The pure part of a cloud call: URL, headers and JSON body. The network
    /// itself stays in the private clean functions — these builders are what
    /// tests pin (hardening R2): auth headers, prompt inclusion, defaults.
    struct CloudRequest {
        let url: URL
        let headers: [String: String]
        let body: [String: Any]
    }

    /// OpenAI-compatible (OpenAI, OpenRouter, Groq, LM Studio…). `baseURL` is
    /// the raw OPENAI_BASE_URL env value (nil → default endpoint; a value of
    /// only slashes falls back to the default too — saner than emitting a
    /// broken relative URL).
    static func openAIRequest(text: String, apiKey: String,
                              baseURL: String?, model: String?,
                              bundleIdentifier: String? = nil) -> CloudRequest? {
        let trimmed = baseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = (trimmed?.isEmpty == false) ? trimmed! : "https://api.openai.com/v1"
        guard let url = URL(string: "\(base)/chat/completions") else { return nil }
        return CloudRequest(
            url: url,
            headers: ["Content-Type": "application/json",
                      "Authorization": "Bearer \(apiKey)"],
            body: ["model": model ?? "gpt-4o-mini",
                   "temperature": 0.2,
                   "messages": [
                       ["role": "system", "content": systemPrompt(forBundleIdentifier: bundleIdentifier)],
                       ["role": "user", "content": text],
                   ]])
    }

    /// Anthropic Messages API. Endpoint and version header are fixed contracts.
    static func anthropicRequest(text: String, apiKey: String,
                                 model: String?,
                                 bundleIdentifier: String? = nil) -> CloudRequest? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        return CloudRequest(
            url: url,
            headers: ["Content-Type": "application/json",
                      "x-api-key": apiKey,
                      "anthropic-version": "2023-06-01"],
            body: ["model": model ?? "claude-3-5-haiku-latest",
                   "max_tokens": 2048,
                   "system": systemPrompt(forBundleIdentifier: bundleIdentifier),
                   "messages": [["role": "user", "content": text]]])
    }

    static func parseOpenAIResponse(_ data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }
        return content
    }

    static func parseAnthropicResponse(_ data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(AnthropicResp.self, from: data),
              let out = decoded.content?.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty else { return nil }
        return out
    }

    // MARK: - OpenAI-compatible (OpenAI, OpenRouter, Groq, LM Studio…)

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message? }
        let choices: [Choice]?
    }

    private static func openAIClean(_ text: String, config: Config,
                                    bundleIdentifier: String? = nil,
                                    transport: SecureCleanupTransport) async -> String? {
        guard let key = config.env["OPENAI_API_KEY"], !key.isEmpty else { return nil }
        guard let request = openAIRequest(text: text, apiKey: key,
                                          baseURL: config.env["OPENAI_BASE_URL"],
                                          model: config.env["CLEANUP_MODEL"],
                                          bundleIdentifier: bundleIdentifier) else { return nil }
        var req = URLRequest(url: request.url, timeoutInterval: 20)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return nil }
        guard let (data, response) = try? await transport.send(req, body: payload),
              response.statusCode == 200 else { return nil }
        let out = stripThinkingJunk(parseOpenAIResponse(data) ?? "")
        return out.isEmpty ? nil : out
    }

    // MARK: - Anthropic

    private static func anthropicClean(_ text: String, config: Config,
                                       bundleIdentifier: String? = nil,
                                       transport: SecureCleanupTransport) async -> String? {
        guard let key = config.env["ANTHROPIC_API_KEY"], !key.isEmpty else { return nil }
        guard let request = anthropicRequest(text: text, apiKey: key,
                                             model: config.env["CLEANUP_MODEL"],
                                             bundleIdentifier: bundleIdentifier) else { return nil }
        var req = URLRequest(url: request.url, timeoutInterval: 20)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return nil }
        guard let (data, response) = try? await transport.send(req, body: payload),
              response.statusCode == 200 else { return nil }
        let out = stripThinkingJunk(parseAnthropicResponse(data) ?? "")
        return out.isEmpty ? nil : out
    }

    private struct AnthropicResp: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]?
    }
}
