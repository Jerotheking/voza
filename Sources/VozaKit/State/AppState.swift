import AppKit
import Combine
import Foundation

enum VozaPhase: Equatable {
    case idle
    case recording(cleanup: Bool)
    case transcribing
    case cleaning
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
    @Published var showOnboarding = false
    @Published var statusMessage: String?

    private let recorder = AudioRecorder.shared
    private let transcriber = Transcriber()
    private var activeModeIsCleanup = false

    private init() {}

    var config: Config { Config.shared }

    func refresh() {
        recent = TranscriptStore.shared.recent
        config.reload()
        showOnboarding = !Permissions.allGranted
    }

    // MARK: - Push to talk

    func startDictation(cleanup: Bool) {
        guard case .idle = phase, !phase.isBusy else { return }
        guard !AudioRecorder.shared.isRecording else { return }
        guard Permissions.microphoneGranted else {
            phase = .failed(L.t("Microphone permission needed", es: "Falta permiso de micrófono"))
            showOnboarding = true
            return
        }
        activeModeIsCleanup = cleanup
        do {
            try recorder.start()
            phase = .recording(cleanup: cleanup)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopDictation() {
        guard case .recording = phase else { return }
        guard let wav = recorder.stop() else {
            phase = .idle
            return
        }
        // Ignore accidental taps shorter than 250 ms.
        if recorder.elapsedSeconds < 0.25 {
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
        let cleanupMode = activeModeIsCleanup

        // 1. Transcribe (never leaves the Mac)
        let language = cfg.resolvedLanguage
        let modelPath = ModelManager.shared.resolvedModelPath(preferredId: cfg.resolvedModelId)
            ?? ModelManager.shared.resolvedModelPath(preferredId: HardwareProfile.recommendedModel())
        var text: String
        do {
            guard let modelPath else { throw TranscriptionError.modelNotFound }
            text = try transcriber.transcribe(wavURL: wavURL, modelPath: modelPath, language: language)
        } catch {
            try? FileManager.default.removeItem(at: wavURL)
            phase = .failed(error.localizedDescription)
            return
        }
        try? FileManager.default.removeItem(at: wavURL) // audio deleted right after transcription

        // 2. Optional AI cleanup
        if cleanupMode {
            phase = .cleaning
            text = await Cleaner.clean(text, config: cfg)
        }

        // 3. Paste + log
        guard Permissions.accessibilityGranted else {
            TranscriptStore.shared.add(text: text, cleaned: cleanupMode)
            refresh()
            phase = .failed(L.t("Accessibility permission needed for paste", es: "Falta permiso de Accesibilidad para pegar"))
            return
        }
        Paster.paste(text)
        TranscriptStore.shared.add(text: text, cleaned: cleanupMode)
        refresh()
        phase = .idle
    }

    // MARK: - Models

    var recommendedModelId: String { HardwareProfile.recommendedModel() }

    func downloadModel(id: String) {
        guard downloadingModelId == nil, let model = WhisperCatalog.byId(id) else { return }
        downloadingModelId = id
        downloadProgress = 0
        Task {
            do {
                try await ModelManager.shared.download(model) { [weak self] p in
                    Task { @MainActor in self?.downloadProgress = p }
                }
                statusMessage = L.t("Model \(id) ready", es: "Modelo \(id) listo")
            } catch {
                phase = .failed(error.localizedDescription)
            }
            downloadingModelId = nil
            downloadProgress = nil
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = L.t("Copied", es: "Copiado")
    }

    func openLogFolder() {
        NSWorkspace.shared.open(TranscriptStore.logDirectory)
    }
}
