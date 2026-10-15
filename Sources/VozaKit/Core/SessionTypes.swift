import Foundation

/// Canonical dictation mode independent of UI localization (V06-AC01).
enum SessionMode: String, Codable, Equatable, Sendable {
    case literal = "literal"
    case polished = "polished"
}

/// Immutable snapshot of user settings captured at the start of a dictation session (V06-AC03, V07-AC04).
/// Mutating `Config` while a session is recording or transcribing never alters an in-flight snapshot.
struct SessionSettingsSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let language: String
    let preferredModelId: String
    let requestedMode: SessionMode
    let autoLearn: Bool
    let playSound: Bool
    let whisperBinary: String?
    let hasCleanupProvider: Bool

    init(
        schemaVersion: Int = SessionSettingsSnapshot.currentSchemaVersion,
        language: String,
        preferredModelId: String,
        requestedMode: SessionMode,
        autoLearn: Bool,
        playSound: Bool,
        whisperBinary: String? = nil,
        hasCleanupProvider: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.language = language
        self.preferredModelId = preferredModelId
        self.requestedMode = requestedMode
        self.autoLearn = autoLearn
        self.playSound = playSound
        self.whisperBinary = whisperBinary
        self.hasCleanupProvider = hasCleanupProvider
    }

    init(from config: Config) {
        let mode: SessionMode = (config.resolvedCleanupMode == "cloud") ? .polished : .literal
        self.init(
            language: config.resolvedLanguage,
            preferredModelId: config.resolvedModelId,
            requestedMode: mode,
            autoLearn: config.autoLearn,
            playSound: config.playSound,
            whisperBinary: config.whisperBinary,
            hasCleanupProvider: config.hasCleanupProvider
        )
    }
}

enum ProcessingStatus: String, Codable, Equatable, Sendable {
    case unchanged
    case rewritten
    case unavailable
    case rejected
    case cancelled
}

/// Explicit outcome of text post-processing (V06-AC02).
/// Distinguishes unchanged success from rewritten, unavailable fallback, rejected output, or cancellation.
struct ProcessingOutcome: Equatable, Sendable {
    let requestedMode: SessionMode
    let appliedMode: SessionMode
    let status: ProcessingStatus
    let text: String
    let didRewrite: Bool
    let reason: String?

    static func literalUnchanged(_ text: String) -> ProcessingOutcome {
        ProcessingOutcome(
            requestedMode: .literal,
            appliedMode: .literal,
            status: .unchanged,
            text: text,
            didRewrite: false,
            reason: nil
        )
    }

    static func polishedSuccess(original: String, result: String) -> ProcessingOutcome {
        let changed = (original != result)
        return ProcessingOutcome(
            requestedMode: .polished,
            appliedMode: .polished,
            status: changed ? .rewritten : .unchanged,
            text: result,
            didRewrite: changed,
            reason: nil
        )
    }

    static func polishedFallback(rawText: String, status: ProcessingStatus, reason: String) -> ProcessingOutcome {
        precondition(status == .unavailable || status == .rejected, "Fallback requires unavailable or rejected status")
        return ProcessingOutcome(
            requestedMode: .polished,
            appliedMode: .literal,
            status: status,
            text: rawText,
            didRewrite: false,
            reason: reason
        )
    }

    static func cancelled(rawText: String = "", requestedMode: SessionMode = .literal) -> ProcessingOutcome {
        ProcessingOutcome(
            requestedMode: requestedMode,
            appliedMode: .literal,
            status: .cancelled,
            text: rawText,
            didRewrite: false,
            reason: "cancelled"
        )
    }
}
