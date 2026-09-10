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
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulse ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
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
