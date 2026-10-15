import Foundation

/// Minimal contract for local speech-to-text execution (V06-AC04, V06-AC05).
protocol SpeechEngine: Sendable {
    func transcribe(
        wavURL: URL,
        modelPath: String,
        language: String,
        initialPrompt: String?
    ) throws -> String
}

/// Production speech engine backed by `Transcriber` (`whisper-cli`).
struct WhisperSpeechEngine: SpeechEngine {
    init() {}

    func transcribe(
        wavURL: URL,
        modelPath: String,
        language: String,
        initialPrompt: String?
    ) throws -> String {
        try Transcriber().transcribe(
            wavURL: wavURL,
            modelPath: modelPath,
            language: language,
            initialPrompt: initialPrompt
        )
    }
}
