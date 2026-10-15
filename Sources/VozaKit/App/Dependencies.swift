import Foundation

/// Single composition root for production services and hermetic test overrides (V06 / V07).
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    var recorder: AudioRecorder
    var speechEngine: any SpeechEngine
    var textProcessor: any TextProcessor
    var hotKeyManager: HotKeyManager

    init(
        recorder: AudioRecorder = .shared,
        speechEngine: any SpeechEngine = WhisperSpeechEngine(),
        textProcessor: any TextProcessor = DefaultTextProcessor(),
        hotKeyManager: HotKeyManager = .shared
    ) {
        self.recorder = recorder
        self.speechEngine = speechEngine
        self.textProcessor = textProcessor
        self.hotKeyManager = hotKeyManager
    }
}
