import Foundation

/// D042 — the dictation flow as ONE deep module (architecture audit
/// 2026-09-21, candidate #2). Owns every ordering invariant of the
/// post-recording flow:
///
///   1. Model resolution: preferred → hardware-recommended fallback, with a
///      user-visible notice whenever the fallback actually fires.
///   2. Transcription OFF the hot path (the production `transcribe` closure
///      keeps its `Task.detached`; `run()` being `@MainActor` only means the
///      orchestration hops between suspensions — whisper never runs on main).
///   3. RTF attributed to the model ACTUALLY used (§3.3), measured with an
///      injectable clock so tests are deterministic.
///   4. The recording WAV is deleted on EVERY path — success, transcription
///      failure, missing accessibility. Audio never outlives the pipeline.
///   5. Learned corrections are applied BEFORE paste; the paste is what the
///      user sees, the log and the learning window come after.
///   6. The correction watcher starts only after the paste is logged (it
///      captures `Paster.lastSession`, which the paste just created).
///
/// Every external effect is an injected closure defaulting to the production
/// implementation, so the whole flow is provable hermetically (V01 rules:
/// no real AX, no whisper, no stores touched by tests).
@MainActor
struct DictationPipeline {
    typealias ResolvedModel = (model: WhisperModel, path: String)

    enum Outcome: Equatable {
        case pasted
        /// User-presentable, already-localized failure reason.
        case failed(String)
    }

    // MARK: Inputs (plain values — no Config singleton reach-in)

    let wavURL: URL
    let recordedSeconds: Double
    let language: String
    let preferredModelId: String
    let learnEnabled: Bool

    // MARK: Seams (defaults = production)

    var resolveModel: (_ preferredId: String, _ language: String) -> ResolvedModel? =
        { preferred, language in
            ModelManager.shared.resolvedModel(preferredId: preferred)
                ?? ModelManager.shared.resolvedModel(preferredId: HardwareProfile.recommendedModel(language: language))
        }
    var transcribe: (URL, _ modelPath: String, _ language: String, _ initialPrompt: String?) async throws -> String =
        { wav, modelPath, language, prompt in
            try await Task.detached(priority: .userInitiated) {
                try Transcriber().transcribe(wavURL: wav, modelPath: modelPath, language: language, initialPrompt: prompt)
            }.value
        }
    var initialPrompt: () -> String? = { CorrectionStore.shared.initialPrompt() }
    var applyCorrections: (String) -> String = { CorrectionStore.apply($0) }
    var clock: () -> Date = { Date() }
    var recordPerformance: (_ rtf: Double, _ modelId: String) -> Void =
        { rtf, model in PerformanceMonitor.shared.record(rtf: rtf, model: model) }
    var onNotice: (String) -> Void = { _ in }
    /// Pastes and returns the session the paste created (nil if none).
    var paste: (String) -> Paster.Session? = { text in
        Paster.paste(text)
        return Paster.lastSession
    }
    var logTranscript: (String) -> Void = { TranscriptStore.shared.add(text: $0, cleaned: false) }
    var startLearning: (Paster.Session) -> Void = { CorrectionWatcher.shared.start(for: $0) }
    var accessibilityGranted: () -> Bool = { Permissions.accessibilityGranted }

    // MARK: Flow

    func run() async -> Outcome {
        // 1. Resolve the model ACTUALLY used (descriptor + path together) so
        // RTF is attributed to the real model, never a silently-fallen-back one.
        guard let resolved = resolveModel(preferredModelId, language) else {
            removeAudio()
            return .failed(TranscriptionError.modelNotFound.localizedDescription)
        }
        if resolved.model.id != preferredModelId {
            onNotice(L.t("Using fallback model \(resolved.model.id)",
                         es: "Usando modelo de respaldo \(resolved.model.id)"))
        }

        // 2. Transcribe. The learned prompt is captured OUTSIDE the timed
        // block so building it never pollutes the RTF measurement.
        let prompt = initialPrompt()
        let startedAt = clock()
        var text: String
        do {
            text = try await transcribe(wavURL, resolved.path, language, prompt)
        } catch {
            removeAudio()
            return .failed(error.localizedDescription)
        }
        let rtf = clock().timeIntervalSince(startedAt) / max(recordedSeconds, 0.5)
        recordPerformance(rtf, resolved.model.id)

        // 3. Audio deleted right after transcription — before paste, on the
        // success path too. From here on the recording no longer exists.
        removeAudio()

        // 4. Learned corrections are the source of truth for what gets pasted.
        text = applyCorrections(text)

        // 5. Paste + log. D032: no LLM cleanup stage — paste is instant after
        // transcription (the Flow lesson). Cloud cleanup returns as an
        // explicit-opt-in feature; the hook point is documented in D032.
        // ✨ history markers stay reserved for it.
        guard accessibilityGranted() else {
            logTranscript(text)
            return .failed(L.t("Accessibility permission needed for paste",
                               es: "Falta permiso de Accesibilidad para pegar"))
        }
        let session = paste(text)
        logTranscript(text)

        // 6. Learning window opens only after the paste is logged — the
        // watcher needs the session the paste just created.
        if learnEnabled, let session {
            startLearning(session)
        }
        return .pasted
    }

    private func removeAudio() {
        try? FileManager.default.removeItem(at: wavURL)
    }
}
