import Foundation

/// D032 — AI cleanup of transcripts: punctuation, capitalization, filler
/// removal, and list/paragraph structuring. CLOUD-ONLY, EXPLICIT OPT-IN.
///
/// PRIVACY POLICY (hardened per external audit v2, §3.8; D032 rewrite):
/// - "plain" (default) → no processing at all: raw transcript pasted.
/// - "cloud" → explicit user choice: OpenAI-compatible (Groq/OpenAI/OpenRouter) → Anthropic,
///   keys from the user's own Keychain or ~/.config/voza/.env. Only already-transcribed
///   text crosses to the cloud, never audio, never by default.
enum Cleaner {

    /// V18 / D065 / D069 — Cloud provider presets and key-prefix auto-routing.
    enum CloudProviderPreset: String, CaseIterable, Identifiable, Sendable {
        case groq
        case openai
        case anthropic
        case openrouter

        var id: String { rawValue }

        var providerShortName: String {
            switch self {
            case .groq:       return "Groq"
            case .openai:     return "OpenAI"
            case .anthropic:  return "Anthropic"
            case .openrouter: return "OpenRouter"
            }
        }

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

        /// Detects the active preset from a pasted API key prefix (`gsk_`, `sk-ant-`, `sk-or-`, `sk-`).
        static func detect(fromKey rawKey: String) -> CloudProviderPreset? {
            let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
            if trimmed.hasPrefix("gsk_") { return .groq }
            if trimmed.hasPrefix("sk-ant-") { return .anthropic }
            if trimmed.hasPrefix("sk-or-") { return .openrouter }
            if trimmed.hasPrefix("sk-") { return .openai }
            return nil
        }

        /// Pure validator for zero-touch clipboard or auto-paste key ingestion (`D067`).
        static func validKeyCandidate(from raw: String?) -> (preset: CloudProviderPreset, key: String)? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 20, trimmed.count <= 256,
                  !trimmed.contains(where: \.isWhitespace),
                  let preset = detect(fromKey: trimmed) else { return nil }
            return (preset, trimmed)
        }

        static func current(in env: [String: String]) -> CloudProviderPreset {
            if let key = env["OPENAI_API_KEY"], let detected = detect(fromKey: key) {
                return detected
            }
            if !(env["ANTHROPIC_API_KEY"] ?? "").isEmpty {
                return .anthropic
            }
            let base = env["OPENAI_BASE_URL"]?.lowercased() ?? ""
            if base.contains("groq.com") { return .groq }
            if base.contains("openrouter.ai") { return .openrouter }
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
        let errorReason: String?

        init(text: String, applied: Bool, provider: String?, errorReason: String? = nil) {
            self.text = text
            self.applied = applied
            self.provider = provider
            self.errorReason = errorReason
        }
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
        var lastError: String?
        for provider in providerChain(for: config.resolvedCleanupMode) {
            guard !Task.isCancelled, Date() < deadline else { break }
            let result: (text: String?, error: String?)
            switch provider {
            case "openai":
                result = await openAIClean(trimmed, config: config, bundleIdentifier: bundleIdentifier, transport: transport)
            case "anthropic":
                result = await anthropicClean(trimmed, config: config, bundleIdentifier: bundleIdentifier, transport: transport)
            default:
                result = (nil, nil)
            }
            if Task.isCancelled {
                return CleaningOutcome(text: text, applied: false, provider: nil)
            }
            if let cleanedText = result.text {
                return CleaningOutcome(text: cleanedText, applied: true, provider: provider)
            }
            if let err = result.error {
                lastError = err
            }
        }
        // Every provider in the chain failed → raw transcript, honestly reported with diagnostic.
        return CleaningOutcome(text: text, applied: false, provider: nil, errorReason: lastError)
    }

    // MARK: - Prompt & App-Aware Context (D065 / D069)

    /// D023 + D069: cleans punctuation, removes fillers, applies voice edit commands
    /// and self-corrections, and formats dictated lists and paragraph breaks.
    static let systemPrompt = """
    You clean and format dictated transcripts. Apply ONLY these transformations:
    1. Fix punctuation and capitalization — always capitalize the first word of the text and of each sentence.
    2. Remove filler words, false starts, and stutters.
    3. EDIT COMMANDS & SELF-CORRECTIONS: phrases like "quita lo de X", "quita eso", "borra lo último", "no, di mejor X", "perdón, X", "digo, X" are spoken EDIT COMMANDS targeting the dictation itself — apply them (delete/rephrase the targeted part) and NEVER output the command itself.
    4. LISTS & PARAGRAPHS:
       - When the speaker dictates a list or enumerated items (e.g., "uno…, dos…, tres…", "primero…, segundo…", "punto uno…", "1…, 2…", or says "en lista", "lista:", "viñetas", "bullet points"), format the items as a clean vertical list using `1. `, `2. `, `3. ` or `- ` with one item per line.
       - When the speaker says "nuevo párrafo" / "new paragraph", insert a blank line (`\\n\\n`); when they say "nueva línea" / "salto de línea" / "new line", insert a line break (`\\n`), and never output the command words themselves.
    5. Keep the speaker's language, meaning and tone. Do not rewrite, translate or add commentary.
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
            return "ACTIVE APP CONTEXT: Email or document editor. Format sentences, lists, and paragraph breaks cleanly while preserving the speaker's exact words."
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

    /// D069 (`make-illegal-states-unrepresentable`): guarantees that `baseURL` and `model`
    /// never disagree with the key prefix (`gsk_` = Groq, `sk-or-` = OpenRouter, `sk-` = OpenAI).
    /// Prevents 401/404 failures when `config.toml` or `OPENAI_BASE_URL` has stale values from another provider.
    static func resolveEndpointAndModel(
        apiKey: String,
        baseURL: String?,
        model: String?
    ) -> (base: String, model: String) {
        let trimmedBase = baseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).NilIfEmpty
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).NilIfEmpty
        let preset = CloudProviderPreset.detect(fromKey: apiKey)

        switch preset {
        case .groq:
            // A `gsk_` key only works on Groq (unless pointing at a local loopback test proxy).
            let base: String
            if let b = trimmedBase, (b.contains("127.0.0.1") || b.contains("localhost")) {
                base = b
            } else {
                base = "https://api.groq.com/openai/v1"
            }
            let resolvedModel: String
            if let m = trimmedModel, !m.hasPrefix("gpt-"), !m.hasPrefix("claude-"), !m.contains("/") {
                resolvedModel = m
            } else {
                resolvedModel = CloudProviderPreset.groq.defaultModel
            }
            return (base, resolvedModel)

        case .openrouter:
            let base: String
            if let b = trimmedBase, (b.contains("127.0.0.1") || b.contains("localhost")) {
                base = b
            } else {
                base = "https://openrouter.ai/api/v1"
            }
            let resolvedModel = trimmedModel ?? CloudProviderPreset.openrouter.defaultModel
            return (base, resolvedModel)

        case .openai, .anthropic, .none:
            let base: String
            if let b = trimmedBase {
                // If an OpenAI `sk-` key is paired with a stale groq.com/openrouter.ai URL, fix it to api.openai.com.
                if preset == .openai && (b.lowercased().contains("groq.com") || b.lowercased().contains("openrouter.ai")) {
                    base = "https://api.openai.com/v1"
                } else {
                    base = b
                }
            } else {
                base = "https://api.openai.com/v1"
            }
            let isOpenAIHost = base.lowercased().contains("api.openai.com")
            let resolvedModel: String
            if let m = trimmedModel {
                // Never send a Groq/OpenRouter-only model ID (e.g. llama-3.3-70b-versatile) to api.openai.com.
                if isOpenAIHost && (m.hasPrefix("llama-") || m.contains("/") || m.hasPrefix("mixtral-") || m.hasPrefix("gemma")) {
                    resolvedModel = "gpt-4o-mini"
                } else {
                    resolvedModel = m
                }
            } else {
                resolvedModel = "gpt-4o-mini"
            }
            return (base, resolvedModel)
        }
    }

    /// OpenAI-compatible (OpenAI, OpenRouter, Groq, LM Studio…). `baseURL` is
    /// the raw OPENAI_BASE_URL env value (nil → default endpoint; a value of
    /// only slashes falls back to the default too — saner than emitting a
    /// broken relative URL).
    static func openAIRequest(text: String, apiKey: String,
                              baseURL: String?, model: String?,
                              bundleIdentifier: String? = nil) -> CloudRequest? {
        let resolved = resolveEndpointAndModel(apiKey: apiKey, baseURL: baseURL, model: model)
        guard let url = URL(string: "\(resolved.base)/chat/completions") else { return nil }
        return CloudRequest(
            url: url,
            headers: ["Content-Type": "application/json",
                      "Authorization": "Bearer \(apiKey)"],
            body: ["model": resolved.model,
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
        let resolvedModel: String
        if let m = model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty, m.hasPrefix("claude-") {
            resolvedModel = m
        } else {
            resolvedModel = "claude-3-5-haiku-latest"
        }
        return CloudRequest(
            url: url,
            headers: ["Content-Type": "application/json",
                      "x-api-key": apiKey,
                      "anthropic-version": "2023-06-01"],
            body: ["model": resolvedModel,
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
                                    transport: SecureCleanupTransport) async -> (text: String?, error: String?) {
        guard let rawKey = config.env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawKey.isEmpty,
              !rawKey.hasPrefix("sk-ant-") else { return (nil, nil) }
        guard let request = openAIRequest(text: text, apiKey: rawKey,
                                          baseURL: config.env["OPENAI_BASE_URL"],
                                          model: config.env["CLEANUP_MODEL"],
                                          bundleIdentifier: bundleIdentifier) else { return (nil, "URL inválida") }
        var req = URLRequest(url: request.url, timeoutInterval: 20)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        // D069: standard User-Agent prevents Cloudflare 1010/403 blocks on api.groq.com.
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Voza/1.0", forHTTPHeaderField: "User-Agent")
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return (nil, "JSON error") }
        do {
            let (data, response) = try await transport.send(req, body: payload)
            guard response.statusCode == 200 else {
                return (nil, "HTTP \(response.statusCode)")
            }
            let out = stripThinkingJunk(parseOpenAIResponse(data) ?? "")
            return out.isEmpty ? (nil, "respuesta vacía") : (out, nil)
        } catch {
            return (nil, "red/timeout")
        }
    }

    // MARK: - Anthropic

    private static func anthropicClean(_ text: String, config: Config,
                                       bundleIdentifier: String? = nil,
                                       transport: SecureCleanupTransport) async -> (text: String?, error: String?) {
        let candidateKey = config.env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines).NilIfEmpty
            ?? (config.env["OPENAI_API_KEY"]?.hasPrefix("sk-ant-") == true ? config.env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        guard let key = candidateKey, !key.isEmpty else { return (nil, nil) }
        guard let request = anthropicRequest(text: text, apiKey: key,
                                             model: config.env["CLEANUP_MODEL"],
                                             bundleIdentifier: bundleIdentifier) else { return (nil, "URL inválida") }
        var req = URLRequest(url: request.url, timeoutInterval: 20)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Voza/1.0", forHTTPHeaderField: "User-Agent")
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return (nil, "JSON error") }
        do {
            let (data, response) = try await transport.send(req, body: payload)
            guard response.statusCode == 200 else {
                return (nil, "HTTP \(response.statusCode)")
            }
            let out = stripThinkingJunk(parseAnthropicResponse(data) ?? "")
            return out.isEmpty ? (nil, "respuesta vacía") : (out, nil)
        } catch {
            return (nil, "red/timeout")
        }
    }

    private struct AnthropicResp: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]?
    }
}

private extension String {
    var NilIfEmpty: String? { isEmpty ? nil : self }
}
