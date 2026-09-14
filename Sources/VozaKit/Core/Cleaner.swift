import Foundation

/// AI cleanup of transcripts: punctuation, capitalization, filler removal.
///
/// PRIVACY POLICY (hardened per external audit v2, §3.8; updated D024):
/// - "auto"  → local only, in-process MLX first, then Ollama IF already
///   installed (never required). Raw transcript otherwise — text NEVER
///   silently crosses to the cloud.
/// - "cloud" → explicit user choice: OpenAI-compatible → Anthropic.
/// - "ollama" → local only via Ollama. "plain" → no processing at all.
/// STT never leaves the Mac; only already-transcribed text goes to the cloud
/// when the user explicitly picks a cloud mode.
enum Cleaner {

    /// What actually happened during cleanup. `applied` is true only when a
    /// provider really transformed the text — history/UI must never claim a
    /// cleaning that did not occur (audit v2 §1.2-5, §3.9).
    struct CleaningOutcome: Sendable {
        let text: String
        let applied: Bool
        let provider: String?   // "mlx" | "ollama" | "openai" | "anthropic" | nil
    }

    /// The exact provider chain for a mode — pure, so tests can prove the
    /// privacy boundary: mode "auto" must never contain a cloud provider.
    /// D024: in-process MLX leads "auto"; Ollama is a fallback for owners who
    /// already run it (Tier C), never an adoption requirement.
    static func providerChain(for mode: String) -> [String] {
        switch mode {
        case "cloud":   return ["openai", "anthropic"]
        case "ollama":  return ["ollama"]
        case "auto":    return ["mlx", "ollama"]     // local-first; cloud is opt-in only
        case "mlx":     return ["mlx"]               // explicit local in-process
        default:        return []                    // "plain" — passthrough
        }
    }

    static func clean(_ text: String, config: Config) async -> CleaningOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.resolvedCleanupMode != "plain",
              !trimmed.isEmpty else { return CleaningOutcome(text: text, applied: false, provider: nil) }

        for provider in providerChain(for: config.resolvedCleanupMode) {
            let t0 = Date()
            let result: String?
            switch provider {
            case "mlx":       result = await mlxClean(trimmed)
            case "ollama":    result = await ollamaClean(trimmed, model: config.resolvedOllamaModel, keepAlive: config.resolvedOllamaKeepAlive)
            case "openai":    result = await openAIClean(trimmed, config: config)
            case "anthropic": result = await anthropicClean(trimmed, config: config)
            default:          result = nil
            }
            let dt = Date().timeIntervalSince(t0)
            if let cleanedText = result {
                // D029: success lines are the latency baseline — the next
                // "it feels slow" report is answered with numbers, not samples.
                CleanupLog.write(provider, "ok", seconds: dt,
                                 detail: "chars=\(cleanedText.count)")
                return CleaningOutcome(text: cleanedText, applied: true, provider: provider)
            }
            // D029: every provider failure is one grep-able line. Slow-
            // failure (timeout/tripwire) vs instant-failure (no server) is
            // visible in the seconds column alone.
            CleanupLog.write(provider, "fail", seconds: dt, detail: "chain continues")
        }
        // Every provider in the chain failed → raw transcript, honestly reported.
        CleanupLog.write("chain", "fallback", detail: "all providers failed — raw pasted")
        return CleaningOutcome(text: text, applied: false, provider: nil)
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You clean dictated transcripts. Apply ONLY these transformations:
    1. Fix punctuation and capitalization — always capitalize the first word of the text and of each sentence.
    2. Remove filler words and stutters.
    3. EDIT COMMANDS: phrases like "quita lo de X", "quita eso", "borra lo último", "no, di mejor X" are spoken EDIT COMMANDS targeting the dictation itself — apply them (delete/rephrase the targeted part) and NEVER output the command itself.
    4. Keep the speaker's language, meaning and tone. Do not rewrite, translate or add anything.
    Output ONLY the cleaned text — no quotes, no commentary.
    """

    /// D023: the request is a pure, testable contract. `/api/chat` with role-
    /// separated messages (generate+system concatenation invites meta-commentary),
    /// `think: false` for hybrid models (qwen3), `keep_alive` bounds RAM
    /// residency, `num_predict` caps generation (latency ceiling).
    static func ollamaRequestBody(text: String, model: String, keepAlive: String) -> [String: Any] {
        return [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "stream": false,
            "think": false,
            "keep_alive": keepAlive,
            "options": ["temperature": 0.2, "num_predict": 400],
        ]
    }

    /// Safety net: if a thinking model ever slips into the config, its
    /// reasoning must never reach the paste (measured: qwen3 emitted entire
    /// responses as reasoning with empty content).
    static func stripThinkingJunk(_ text: String) -> String {
        guard let start = text.range(of: "<think>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Unclosed block (truncated by num_predict): no answer exists after it —
        // the entire remainder is reasoning. Return empty → caller falls back
        // to the raw transcript instead of ever pasting reasoning.
        guard let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) else { return "" }
        let out = text.replacingCharacters(in: text.startIndex..<end.upperBound, with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - MLX in-process (D024, local default)

    /// In-process engine call: same prompt, same hygiene (stripThinkingJunk
    /// applied here because MLXEngine returns raw output by contract). The
    /// first call on a fresh install downloads the QAT 4B (~2.5 GB) through
    /// the Hub cache; later calls reuse the resident weights (0.8 s warm).
    private static func mlxClean(_ text: String) async -> String? {
        guard let outcome = await MLXEngine.complete(text, systemPrompt: systemPrompt) else { return nil }
        let out = stripThinkingJunk(outcome.rawText)
        return out.isEmpty ? nil : out
    }

    // MARK: - Ollama (local fallback, Tier C)

    private static func ollamaClean(_ text: String, model: String, keepAlive: String) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ollamaRequestBody(text: text, model: model, keepAlive: keepAlive)
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data

        guard let (respData, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct OllamaResp: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
            let doneReason: String?
        }
        guard let decoded = try? JSONDecoder().decode(OllamaResp.self, from: respData),
              let raw = decoded.message?.content else { return nil }
        // D028: done_reason "length" means the token budget was exhausted —
        // the answer never finished (measured live: qwen3 burned 1024 tokens
        // thinking; truncated output pasted mid-sentence). Nil → D016 fallback.
        if decoded.doneReason == "length" {
            print("[Cleaner] ollama done_reason=length — treating as truncated")
            return nil
        }
        let out = stripThinkingJunk(raw)
        return out.isEmpty ? nil : out
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
                              baseURL: String?, model: String?) -> CloudRequest? {
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
                       ["role": "system", "content": systemPrompt],
                       ["role": "user", "content": text],
                   ]])
    }

    /// Anthropic Messages API. Endpoint and version header are fixed contracts.
    static func anthropicRequest(text: String, apiKey: String,
                                 model: String?) -> CloudRequest? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        return CloudRequest(
            url: url,
            headers: ["Content-Type": "application/json",
                      "x-api-key": apiKey,
                      "anthropic-version": "2023-06-01"],
            body: ["model": model ?? "claude-3-5-haiku-latest",
                   "max_tokens": 2048,
                   "system": systemPrompt,
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

    private static func openAIClean(_ text: String, config: Config) async -> String? {
        guard let key = config.env["OPENAI_API_KEY"], !key.isEmpty else { return nil }
        guard let request = openAIRequest(text: text, apiKey: key,
                                          baseURL: config.env["OPENAI_BASE_URL"],
                                          model: config.env["CLEANUP_MODEL"]) else { return nil }
        var req = URLRequest(url: request.url, timeoutInterval: 60)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return nil }
        req.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseOpenAIResponse(data)
    }

    // MARK: - Anthropic

    private static func anthropicClean(_ text: String, config: Config) async -> String? {
        guard let key = config.env["ANTHROPIC_API_KEY"], !key.isEmpty else { return nil }
        guard let request = anthropicRequest(text: text, apiKey: key,
                                             model: config.env["CLEANUP_MODEL"]) else { return nil }
        var req = URLRequest(url: request.url, timeoutInterval: 60)
        req.httpMethod = "POST"
        for (field, value) in request.headers { req.setValue(value, forHTTPHeaderField: field) }
        guard let payload = try? JSONSerialization.data(withJSONObject: request.body) else { return nil }
        req.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseAnthropicResponse(data)
    }

    private struct AnthropicResp: Decodable {
        struct Block: Decodable { let text: String? }
        let content: [Block]?
    }
}
