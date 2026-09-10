import AppKit
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
    private let hudSize = NSSize(width: 190, height: 58)

    func update(phase: VozaPhase) {
        if phase.isBusy {
            show()
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
                          y: visible.minY + 48,
                          width: hudSize.width,
                          height: hudSize.height),
                   display: true)
    }
}

struct DictationHUDView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            switch appState.phase {
            case .recording(let cleanup):
                LevelBars(tint: cleanup ? Theme.accent : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t(cleanup ? "Recording · cleanup" : "Recording",
                             es: cleanup ? "Grabando · limpieza" : "Grabando"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(format: "%.0f s", appState.elapsedSeconds))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("Transcribing…", es: "Transcribiendo…"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(L.t("100% on your Mac", es: "100% en tu Mac"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .cleaning:
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text(L.t("Polishing text…", es: "Puliendo texto…"))
                    .font(.system(size: 12, weight: .semibold))
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

/// Audio-reactive bars (D021): driven by the recorder's real RMS level,
/// sampled at ~20 Hz via TimelineView. Move when you speak, rest when you
/// don't — TypeWhisper-style feedback that the mic hears YOU.
struct LevelBars: View {
    var tint: Color = .red

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { _ in
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: Self.height(bar: i, level: AudioRecorder.shared.level))
                }
            }
            .frame(height: 24, alignment: .center)
        }
    }

    /// Pure mapping so tests can pin it: each bar samples a different sine
    /// phase of the level, so bars move unevenly (natural look) and never
    /// fall below 5 pt or above 22 pt.
    static func height(bar: Int, level: Double) -> CGFloat {
        let phase = Double(bar) * .pi / 2
        let jitter = 0.7 + 0.3 * sin(phase + level * 6)
        return min(22, max(5, 5 + CGFloat(level * 17 * jitter)))
    }
}
