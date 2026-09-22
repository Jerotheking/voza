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
                ramGB: HardwareProfile.totalRAMGB,
                language: config.resolvedLanguage
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
        Task { await self.runPipeline(wavURL: wav) }
    }

    /// D042: the flow itself lives in DictationPipeline (deep module with
    /// injected seams). AppState only maps its outcome onto published UI
    /// state — zero orchestration logic lives here anymore.
    private func runPipeline(wavURL: URL) async {
        var pipeline = DictationPipeline(
            wavURL: wavURL,
            recordedSeconds: recordedSeconds,
            language: config.resolvedLanguage,
            preferredModelId: config.resolvedModelId,
            learnEnabled: config.autoLearn
        )
        pipeline.onNotice = { [weak self] message in
            self?.statusMessage = message
        }
        // P1-b (agy re-review 2026-09-22): a cloud-cleanup failure must be
        // ANNOUNCED, never silent — the raw paste alone reads as a broken
        // Pulido mode. Same surface as the fallback-model notice.
        pipeline.onCleanupUnavailable = { [weak self] in
            self?.statusMessage = L.t("Cloud cleanup unavailable — pasted raw",
                                      es: "Limpieza IA no disponible — pegado directo")
        }
        let outcome = await pipeline.run()
        switch outcome {
        case .pasted:
            if config.playSound {
                NSSound(named: "Tink")?.play()
            }
            // First-dictation teaching moment: exactly once, right after the
            // first successful paste — the gesture and the learn-by-typing
            // habit are taught while they're happening, not in a setup screen.
            if FirstRunExperience.firstDictationPending {
                FirstRunExperience.markFirstDictationShown()
                FirstDictationPanelController.shared.show()
            }
            refresh()
            phase = .idle
        case .failed(let reason):
            refresh()
            phase = .failed(reason)
        }
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
