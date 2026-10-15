import Foundation

/// Minimal contract for post-transcription text processing (V06-AC02, V06-AC04).
protocol TextProcessor: Sendable {
    func process(
        rawText: String,
        snapshot: SessionSettingsSnapshot,
        cleanClosure: (@Sendable (String) async -> Cleaner.CleaningOutcome)?
    ) async -> ProcessingOutcome
}

struct DefaultTextProcessor: TextProcessor {
    init() {}

    func process(
        rawText: String,
        snapshot: SessionSettingsSnapshot,
        cleanClosure: (@Sendable (String) async -> Cleaner.CleaningOutcome)? = nil
    ) async -> ProcessingOutcome {
        if Task.isCancelled {
            return .cancelled(rawText: rawText, requestedMode: snapshot.requestedMode)
        }
        guard snapshot.requestedMode == .polished else {
            return .literalUnchanged(rawText)
        }
        guard snapshot.hasCleanupProvider, let cleanClosure else {
            return .polishedFallback(rawText: rawText, status: .unavailable, reason: "no_provider")
        }
        let outcome = await cleanClosure(rawText)
        if Task.isCancelled {
            return .cancelled(rawText: rawText, requestedMode: .polished)
        }
        if outcome.applied {
            let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .polishedFallback(rawText: rawText, status: .rejected, reason: "empty_output")
            }
            return .polishedSuccess(original: rawText, result: trimmed)
        } else {
            return .polishedFallback(rawText: rawText, status: .unavailable, reason: "provider_failed")
        }
    }
}
