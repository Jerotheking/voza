import Foundation

/// AI cleanup of transcripts: punctuation, capitalization, filler removal.
/// Priority: local Ollama (free, offline) → OpenAI-compatible cloud → Anthropic → plain passthrough.
/// STT never leaves the Mac; only the already-transcribed text goes to the cloud when configured.
enum Cleaner {

    static func clean(_ text: String, config: Config) async -> String {
        guard config.resolvedCleanupMode != "plain" else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        switch config.resolvedCleanupMode {
        case "ollama":
            return await ollamaClean(text, model: config.resolvedOllamaModel) ?? text
        case "cloud":
            if let key = config.env["OPENAI_API_KEY"], !key.isEmpty,
               let out = await openAIClean(text, config: config) { return out }
            if let key = config.env["ANTHROPIC_API_KEY"], !key.isEmpty,
               let out = await anthropicClean(text, config: config) { return out }
            return text
        default: // "auto"
            if let out = await ollamaClean(text, model: config.resolvedOllamaModel) { return out }
            if let key = config.env["OPENAI_API_KEY"], !key.isEmpty,
               let out = await openAIClean(text, config: config) { return out }
            if let key = config.env["ANTHROPIC_API_KEY"], !key.isEmpty,
               let out = await anthropicClean(text, config: config) { return out }
            return text
        }
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are a dictation cleaner. Fix punctuation and capitalization, remove filler words \
    ("um", "uh", "like" as filler, "este...", "o sea" when filler, repeated words), and fix \
    obvious speech-to-text errors. Preserve the speaker's language, meaning, tone and wording. \
    Never answer, never add commentary. Output ONLY the cleaned text.
    """

    // MARK: - Ollama (local)

    private static func ollamaClean(_ text: String, model: String) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // /no_think keeps qwen3 from emitting reasoning tokens.
        let body: [String: Any] = [
            "model": model,
            "prompt": "\(text)\n\n/no_think",
            "system": systemPrompt,
            "stream": false,
            "options": ["temperature": 0.2, "num_predict": 2048],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data

        guard let (respData, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct OllamaResp: Decodable { let response: String }
        guard let decoded = try? JSONDecoder().decode(OllamaResp.self, from: respData) else { return nil }
        let out = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    // MARK: - OpenAI-compatible (OpenAI, OpenRouter, Groq, LM Studio…)

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message? }
        let choices: [Choice]?
    }

    private static func openAIClean(_ text: String, config: Config) async -> String? {
        guard let key = config.env["OPENAI_API_KEY"], !key.isEmpty else { return nil }
        let base = config.env["OPENAI_BASE_URL"]?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://api.openai.com/v1"
        guard let url = URL(string: "\(base)/chat/completions") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.env["CLEANUP_MODEL"] ?? "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }
        return content
    }

    // MARK: - Anthropic

    private static func anthropicClean(_ text: String, config: Config) async -> String? {
        guard let key = config.env["ANTHROPIC_API_KEY"], !key.isEmpty else { return nil }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": config.env["CLEANUP_MODEL"] ?? "claude-3-5-haiku-latest",
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload

        struct AnthropicResp: Decodable {
            struct Block: Decodable { let text: String? }
            let content: [Block]?
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AnthropicResp.self, from: data),
              let out = decoded.content?.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty else { return nil }
        return out
    }
}
