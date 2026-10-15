import AppKit
import Combine
import SwiftUI

/// Floating dictation HUD (owner decision D020, TypeWhisper-style): a small,
/// non-activating panel that makes the recording → transcribing → cleaning
/// lifecycle glanceable while the popover stays closed. Appears only while
/// busy; never steals focus or key; survives fullscreen spaces.
///
/// The view is reactive: it reads `AppState.shared` published fields, so the
/// elapsed timer ticks without the controller touching the panel per second.
@MainActor
final class DictationHUDController {
    static let shared = DictationHUDController()

    private var panel: NSPanel?
    private let hudSize = NSSize(width: 184, height: 42)

    func update(phase: VozaPhase) {
        if phase.isBusy {
            show()
            // The first-dictation celebration lives at the same anchor; a
            // new dictation always wins the spot instantly.
            FirstDictationPanelController.shared.hide()
        } else {
            hide()
        }
    }

    private func show() {
        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: hudSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView:
            DictationHUDView().environmentObject(AppState.shared))
        panel = p
        return p
    }

    /// Bottom-center of the key screen, above the dock (visibleFrame already
    /// excludes it). Deliberately near where the user's eyes already are.
    private func position(_ p: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        p.setFrame(NSRect(x: visible.midX - hudSize.width / 2,
                          y: visible.minY + 40,
                          width: hudSize.width,
                          height: hudSize.height),
                   display: true)
    }
}

struct DictationHUDView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var levelModel = HUDLevelModel()

    var body: some View {
        HStack(spacing: 9) {
            switch appState.phase {
            case .recording:
                LevelBars(tint: .red)
                    .environmentObject(levelModel)
                VStack(alignment: .leading, spacing: 0) {
                    Text(appState.isHandsFree
                         ? L.t("Hands-free", es: "Manos libres")
                         : L.t("Recording", es: "Grabando"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(appState.isHandsFree
                         ? L.t("\(String(format: "%.0f s", appState.elapsedSeconds)) · tap ⌥",
                               es: "\(String(format: "%.0f s", appState.elapsedSeconds)) · toca ⌥")
                         : String(format: "%.0f s", appState.elapsedSeconds))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .transcribing:
                ProgressView()
                    .controlSize(.mini)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.t("Transcribing…", es: "Transcribiendo…"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(L.t("on your Mac", es: "en tu Mac"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

/// Drives the HUD bars deterministically: a 30 Hz main-thread timer samples
/// the recorder's raw level and applies VU-style dynamics — fast attack,
/// slow release — so bars snap up when you speak and glide down when you
/// stop. Replaces TimelineView, which re-renders unreliably inside a
/// non-activating NSPanel (the bug the owner caught: static bars).
@MainActor
final class HUDLevelModel: ObservableObject {
    @Published private(set) var displayLevel: Double = 0
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    init() {
        cancellable = AppState.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                if case .recording = phase { self?.start() } else { self?.stop() }
            }
    }

    deinit {
        cancellable?.cancel()
        timer?.invalidate()
    }

    private func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let target = AudioRecorder.shared.isRecording ? AudioRecorder.shared.level : 0
                self.displayLevel = Self.next(display: self.displayLevel, target: target)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        displayLevel = 0
    }

    /// Pure dynamics seam (tested): attacks at 55%/tick, releases at 18%.
    nonisolated static func next(display: Double, target: Double) -> Double {
        if target > display {
            return display + (target - display) * 0.55
        }
        return display * 0.82 + target * 0.18
    }
}

/// First-dictation teaching moment (one-shot, FirstRunExperience): shown
/// right after the first successful paste, while muscle memory is forming.
/// Teaches the two habits that make Voza stick — the hold-a-Option gesture
/// and typing-to-teach — then leaves the user alone forever. Same visual
/// language and anchor as the dictation HUD.
@MainActor
final class FirstDictationPanelController {
    static let shared = FirstDictationPanelController()

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private let panelSize = NSSize(width: 340, height: 118)
    private static let autoDismissSeconds: TimeInterval = 10

    func show() {
        let p = ensurePanel()
        position(p)
        p.orderFrontRegardless()
        scheduleAutoDismiss()
    }

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
    }

    private func scheduleAutoDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissSeconds, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: FirstDictationView(onDismiss: { [weak self] in self?.hide() }))
        panel = p
        return p
    }

    /// Same anchor as the dictation HUD: bottom-center, above the dock.
    private func position(_ p: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        p.setFrame(NSRect(x: visible.midX - panelSize.width / 2,
                          y: visible.minY + 40,
                          width: panelSize.width,
                          height: panelSize.height),
                   display: true)
    }
}

struct FirstDictationView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave")
                    .foregroundStyle(Theme.accent)
                Text(L.t("That was your first dictation!", es: "¡Ese fue tu primer dictado!"))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(L.t("Hold an Option key, talk, release — in any app.",
                     es: "Mantén una tecla Option, habla y suelta — en cualquier app."))
                .font(.system(size: 12))
            Text(L.t("A word wrong? Just fix it by typing — Voza learns your corrections and applies them next time. Everything stays on your Mac.",
                     es: "¿Alguna palabra mal? Corrígela tecleando — Voza aprende tus correcciones y las aplica la próxima vez. Todo se queda en tu Mac."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

/// Audio-reactive bars (D021/D022): driven by the smoothed mic level.
struct LevelBars: View {
    @EnvironmentObject var levelModel: HUDLevelModel
    var tint: Color = .red

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: Self.height(bar: i, level: levelModel.displayLevel))
            }
        }
        .frame(height: 20, alignment: .center)
        .animation(.linear(duration: 0.04), value: levelModel.displayLevel)
    }

    /// Pure mapping so tests can pin it: each bar samples a different sine
    /// phase of the level, so bars move unevenly (natural look) and never
    /// fall below 3 pt or above 17 pt.
    static func height(bar: Int, level: Double) -> CGFloat {
        let phase = Double(bar) * .pi / 2
        let jitter = 0.7 + 0.3 * sin(phase + level * 6)
        return min(17, max(3, 3 + CGFloat(level * 14 * jitter)))
    }
}
