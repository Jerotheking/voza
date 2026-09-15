import AppKit
import Combine
import Foundation

enum VozaPhase: Equatable {
    case idle
    case recording
    case transcribing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .idle, .failed: return false
        default: return true
        }
    }
}

/// Central observable state driving the menu bar icon, popover and pipeline.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: VozaPhase = .idle
    @Published var recent: [TranscriptEntry] = []
    @Published var downloadProgress: Double?
    @Published var downloadingModelId: String?
    @Published var downloadETA: String?
    @Published var perfSuggestion: PerformanceMonitor.Suggestion?
    @Published var showOnboarding = false
    @Published var statusMessage: String?
    @Published var elapsedSeconds: Double = 0

    let license = LicenseManager.shared

    private let recorder = AudioRecorder.shared
    private var tickTimer: Timer?
    private var recordedSeconds: Double = 0
    private var downloadStartAt: Date?

    private init() {}

    var config: Config { Config.shared }

    func refresh() {
        recent = TranscriptStore.shared.recent
        config.reload()
        showOnboarding = !Permissions.allGranted
        if !phase.isBusy {
            perfSuggestion = PerformanceMonitor.shared.suggestion(
                currentModel: config.resolvedModelId,
                ramGB: HardwareProfile.totalRAMGB
            )
        }
    }

    // MARK: - Push to talk

    func startDictation() {
        // Allow (re)starting from both .idle and .failed — a failed attempt
        // must never require quitting to retry. Busy phases block new starts.
        guard !phase.isBusy else { return }
        guard !AudioRecorder.shared.isRecording else { return }
        guard Permissions.microphoneGranted else {
            phase = .failed(L.t("Microphone permission needed", es: "Falta permiso de micrófono"))
            showOnboarding = true
            return
        }
        do {
            try recorder.start()
            elapsedSeconds = 0
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, case .recording = self.phase else { return }
                    self.elapsedSeconds = self.recorder.elapsedSeconds
                }
            }
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopDictation() {
        guard case .recording = phase else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        recordedSeconds = elapsedSeconds
        guard let wav = recorder.stop() else {
            phase = .idle
            return
        }
        // Ignore accidental taps shorter than 250 ms.
        if elapsedSeconds < 0.25 {
            recorder.cancel()
            try? FileManager.default.removeItem(at: wav)
            phase = .idle
            return
        }
        phase = .transcribing
        Task { await self.pipeline(wavURL: wav) }
    }

    private func pipeline(wavURL: URL) async {
        let cfg = config

        // 1. Transcribe (never leaves the Mac). The whisper.cpp process is blocking
        // (it polls with Thread.sleep), so it MUST run off the MainActor — otherwise
        // the menu bar and hotkeys freeze for the whole transcription (audit v2 §3.4).
        let language = cfg.resolvedLanguage
        let preferredId = cfg.resolvedModelId
        var text: String
        do {
            // Resolve the model ACTUALLY used (descriptor + path together) so RTF is
            // attributed to the real model, never a silently-fallen-back one (§3.3).
            guard let resolved = ModelManager.shared.resolvedModel(preferredId: preferredId)
                ?? ModelManager.shared.resolvedModel(preferredId: HardwareProfile.recommendedModel(language: language))
            else { throw TranscriptionError.modelNotFound }
            if resolved.model.id != preferredId {
                statusMessage = L.t("Using fallback model \(resolved.model.id)",
                                    es: "Usando modelo de respaldo \(resolved.model.id)")
            }
            let modelPath = resolved.path
            // Learned vocabulary biases decoding BEFORE the model runs; captured
            // OUTSIDE the timed block so it never pollutes the RTF measurement.
            let prompt = CorrectionStore.shared.initialPrompt()
            let startedAt = Date()
            text = try await Task.detached(priority: .userInitiated) {
                try Transcriber().transcribe(wavURL: wavURL, modelPath: modelPath, language: language, initialPrompt: prompt)
            }.value
            let rtf = Date().timeIntervalSince(startedAt) / max(recordedSeconds, 0.5)
            PerformanceMonitor.shared.record(rtf: rtf, model: resolved.model.id)
        } catch {
            try? FileManager.default.removeItem(at: wavURL)
            phase = .failed(error.localizedDescription)
            return
        }
        try? FileManager.default.removeItem(at: wavURL) // audio deleted right after transcription
        // Learned corrections are the source of truth for what gets pasted.
        text = CorrectionStore.apply(text)

        // 2. Paste + log. D032: no LLM cleanup stage — paste is instant after
        // transcription (the Flow lesson: on-device 4B cleanup cannot win the
        // latency/reliability war on real machines). Cloud cleanup returns as
        // an explicit-opt-in feature; the pipeline hook point is documented in
        // DECISIONS.md D032. ✨ history markers stay reserved for it.
        guard Permissions.accessibilityGranted else {
            TranscriptStore.shared.add(text: text, cleaned: false)
            refresh()
            phase = .failed(L.t("Accessibility permission needed for paste", es: "Falta permiso de Accesibilidad para pegar"))
            return
        }
        Paster.paste(text)
        TranscriptStore.shared.add(text: text, cleaned: false)
        if cfg.autoLearn, let session = Paster.lastSession {
            CorrectionWatcher.shared.start(for: session)
        }
        if cfg.playSound {
            NSSound(named: "Tink")?.play()
        }
        // First-dictation teaching moment: exactly once, right after the first
        // successful paste — the gesture and the learn-by-typing habit are
        // taught while they're happening, not in a forgotten setup screen.
        if FirstRunExperience.firstDictationPending {
            FirstRunExperience.markFirstDictationShown()
            FirstDictationPanelController.shared.show()
        }
        refresh()
        phase = .idle
    }

    // MARK: - Models

    var recommendedModelId: String { HardwareProfile.recommendedModel(language: config.resolvedLanguage) }

    func downloadModel(id: String, switchWhenDone: Bool = false) {
        guard downloadingModelId == nil, let model = WhisperCatalog.byId(id) else { return }
        let free = ReadinessChecker.freeDiskMB()
        let requiredMB = ReadinessChecker.requiredFreeMB(for: model)
        guard free >= requiredMB else {
            phase = .failed(L.t("Only \(free) MB free — \(id) needs about \(requiredMB) MB. Free up space and retry.",
                                es: "Solo \(free) MB libres — \(id) necesita unos \(requiredMB) MB. Libera espacio e intenta de nuevo."))
            return
        }
        downloadingModelId = id
        downloadProgress = 0
        downloadETA = nil
        downloadStartAt = Date()
        Task {
            do {
                try await ModelManager.shared.download(model) { [weak self] p in
                    Task { @MainActor in
                        self?.downloadProgress = p
                        if let start = self?.downloadStartAt {
                            let elapsed = Date().timeIntervalSince(start)
                            if p > 0.02, elapsed > 1.5 {
                                let remaining = max(elapsed / p - elapsed, 0)
                                self?.downloadETA = Self.formatETA(remaining)
                            }
                        }
                    }
                }
                if switchWhenDone {
                    config.setModel(id)
                    statusMessage = L.t("Switched to \(id)", es: "Cambiado a \(id)")
                } else {
                    statusMessage = L.t("Model \(id) ready", es: "Modelo \(id) listo")
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
            downloadingModelId = nil
            downloadProgress = nil
            downloadETA = nil
            downloadStartAt = nil
        }
    }

    /// One-tap model change from a performance suggestion.
    func applySuggestion() {
        guard let suggestion = perfSuggestion else { return }
        perfSuggestion = nil
        if let model = WhisperCatalog.byId(suggestion.targetModelId),
           !ModelManager.shared.isDownloaded(model) {
            downloadModel(id: suggestion.targetModelId, switchWhenDone: true)
        } else {
            config.setModel(suggestion.targetModelId)
            statusMessage = L.t("Switched to \(suggestion.targetModelId)", es: "Cambiado a \(suggestion.targetModelId)")
            refresh()
        }
    }

    func dismissSuggestion() {
        if let suggestion = perfSuggestion {
            PerformanceMonitor.shared.dismiss(suggestion)
        }
        perfSuggestion = nil
    }

    nonisolated static func formatETA(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = L.t("Copied", es: "Copiado")
    }

    /// Learns from a user-corrected history row (✏️) and re-pastes the fixed
    /// text at the cursor, so fixing a row doubles as "redo the paste".
    /// D033: oversized diffs are refused with an honest status instead of
    /// silently poisoning the dictionary (they'd never fire as replacements
    /// and would starve the whisper prompt budget).
    func learnCorrection(entry: TranscriptEntry, corrected: String) {
        if let pair = CorrectionStore.diffCorrection(original: entry.text, corrected: corrected) {
            if CorrectionStore.shared.record(heard: pair.heard, said: pair.said) != nil {
                statusMessage = L.t("Learned — I'll write it right next time", es: "Aprendido — la próxima vez lo escribiré bien")
            } else {
                statusMessage = L.t("Too long to learn — fix it word by word", es: "Demasiado largo para aprenderlo — corrígelo palabra por palabra")
            }
        }
        repaste(corrected)
    }

    /// Pastes given text at the current cursor location (history fixes).
    func repaste(_ text: String) {
        guard Permissions.accessibilityGranted else {
            phase = .failed(L.t("Accessibility permission needed for paste", es: "Falta permiso de Accesibilidad para pegar"))
            return
        }
        Paster.paste(text)
        if config.playSound {
            NSSound(named: "Tink")?.play()
        }
    }

    func openLogFolder() {
        NSWorkspace.shared.open(TranscriptStore.logDirectory)
    }
}
