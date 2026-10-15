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
    @Published var downloadError: String?
    private(set) var activeSessionID: UUID?
    private(set) var activeSessionSnapshot: SessionSettingsSnapshot?
    private var activePipelineTask: Task<Void, Never>?
    @Published var perfSuggestion: PerformanceMonitor.Suggestion?
    @Published var showOnboarding = false
    @Published var statusMessage: String?
    @Published var elapsedSeconds: Double = 0

    let license = LicenseManager.shared

    let dependencies = AppDependencies.shared
    private var recorder: AudioRecorder { dependencies.recorder }
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
        // V07-AC03: Busy phases block new starts; never spawn a second recorder/process.
        guard !phase.isBusy else { return }
        guard !AudioRecorder.shared.isRecording else { return }
        guard Permissions.microphoneGranted else {
            phase = .failed(L.t("Microphone permission needed", es: "Falta permiso de micrófono"))
            showOnboarding = true
            return
        }
        let sessionID = UUID()
        let snapshot = SessionSettingsSnapshot(from: config)
        do {
            try recorder.start()
            activeSessionID = sessionID
            activeSessionSnapshot = snapshot
            elapsedSeconds = 0
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // V07-AC05: ignore timer ticks from any superseded session ID.
                    guard let self, self.activeSessionID == sessionID, case .recording = self.phase else { return }
                    self.elapsedSeconds = self.recorder.elapsedSeconds
                }
            }
            phase = .recording
        } catch {
            activeSessionID = nil
            activeSessionSnapshot = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func stopDictation() {
        guard case .recording = phase, let sessionID = activeSessionID else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        recordedSeconds = elapsedSeconds
        guard let wav = recorder.stop() else {
            activeSessionID = nil
            activeSessionSnapshot = nil
            phase = .idle
            return
        }
        // Ignore accidental taps shorter than 250 ms.
        if elapsedSeconds < 0.25 {
            recorder.cancel()
            try? FileManager.default.removeItem(at: wav)
            activeSessionID = nil
            activeSessionSnapshot = nil
            phase = .idle
            return
        }
        let snapshot = activeSessionSnapshot ?? SessionSettingsSnapshot(from: config)
        phase = .transcribing
        activePipelineTask = Task { [weak self] in
            await self?.runPipeline(wavURL: wav, sessionID: sessionID, snapshot: snapshot)
        }
    }

    /// V07-AC02: Cancels the active session immediately; invalidates `activeSessionID`
    /// first so any late async STT/cleanup completion is ignored.
    func cancelDictation() {
        activeSessionID = nil
        activeSessionSnapshot = nil
        tickTimer?.invalidate()
        tickTimer = nil
        activePipelineTask?.cancel()
        activePipelineTask = nil
        recorder.cancel()
        if phase.isBusy {
            phase = .idle
        }
    }

    /// D042 + V07: the flow itself lives in DictationPipeline (deep module with
    /// injected seams). AppState only maps its outcome onto published UI
    /// state if `sessionID` still matches `activeSessionID` (V07-AC02, V07-AC05).
    private func runPipeline(wavURL: URL, sessionID: UUID, snapshot: SessionSettingsSnapshot) async {
        var pipeline = DictationPipeline(
            wavURL: wavURL,
            recordedSeconds: recordedSeconds,
            language: snapshot.language,
            preferredModelId: snapshot.preferredModelId,
            learnEnabled: snapshot.autoLearn
        )
        pipeline.isCancelled = { [weak self] in
            Task.isCancelled || self?.activeSessionID != sessionID
        }
        pipeline.onNotice = { [weak self] message in
            guard let self, self.activeSessionID == sessionID else { return }
            self.statusMessage = message
        }
        pipeline.onCleanupUnavailable = { [weak self] in
            guard let self, self.activeSessionID == sessionID else { return }
            self.statusMessage = L.t("Cloud cleanup unavailable — pasted raw",
                                     es: "Limpieza IA no disponible — pegado directo")
        }
        let outcome = await pipeline.run()
        guard self.activeSessionID == sessionID else { return }
        self.activeSessionID = nil
        self.activeSessionSnapshot = nil
        self.activePipelineTask = nil

        switch outcome {
        case .pasted:
            if snapshot.playSound {
                NSSound(named: "Tink")?.play()
            }
            if FirstRunExperience.firstDictationPending {
                FirstRunExperience.markFirstDictationShown()
                FirstDictationPanelController.shared.show()
            }
            refresh()
            phase = .idle
        case .cancelled:
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
            let msg = L.t("Only \(free) MB free — \(id) needs about \(requiredMB) MB. Free up space and retry.",
                          es: "Solo \(free) MB libres — \(id) necesita unos \(requiredMB) MB. Libera espacio e intenta de nuevo.")
            downloadError = msg
            if !phase.isBusy { phase = .failed(msg) }
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
                downloadError = error.localizedDescription
                if !phase.isBusy {
                    phase = .failed(error.localizedDescription)
                } else {
                    statusMessage = error.localizedDescription
                }
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
