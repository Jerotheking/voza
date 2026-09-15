import SwiftUI

extension NSApplication {
    /// Opens the SwiftUI Settings scene and guarantees it lands in front.
    /// Voza is an LSUIElement (accessory) app: macOS 14+ cooperative
    /// activation routinely denies focus, so the settings window otherwise
    /// opens BEHIND the frontmost app — looking exactly like "the button
    /// does nothing". The activation opportunity is only valid while the
    /// user's click is being handled, so activate FIRST, then open, then
    /// force the window to front on the next run-loop turn.
    func openSettingsInFront() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
        guard sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) else { return }
        DispatchQueue.main.async {
            if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}

public struct VozaApp: App {
    public init() {}
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var appState = AppState.shared

    public var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(phase: appState.phase)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.phase) { _, newPhase in
            // Floating HUD (D020): the lifecycle is glanceable without opening
            // the popover. Sync must also run when this window is closed, so
            // it lives on the scene, not inside the popover content.
            DictationHUDController.shared.update(phase: newPhase)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

/// Floating setup window: unlike the MenuBarExtra panel, it does NOT dismiss
/// when the user clicks System Settings to grant a permission — it stays on
/// screen until setup completes or the user closes it explicitly.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
                               styleMask: [.titled, .closable],
                               backing: .buffered, defer: false)
            win.title = "Voza — Setup"
            win.contentView = NSHostingView(rootView: OnboardingView().environmentObject(appState))
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close without destroying the controller — `show` can bring it back.
    func closeIfVisible() {
        window?.performClose(nil)
    }
}

@MainActor
struct MenuBarLabel: View {
    let phase: VozaPhase

    var body: some View {
        switch phase {
        case .idle, .failed:
            Image(systemName: "mic")
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red)
        case .transcribing:
            Image(systemName: "waveform")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKeyManager.shared.start()
        TranscriptStore.shared.loadRecent(limit: 10)

        // Wire push-to-talk to the shared AppState. D032: one behavior — any
        // Option key dictates and the raw transcript is pasted instantly.
        let appState = AppState.shared
        HotKeyManager.shared.onPressNormal = { appState.startDictation() }
        HotKeyManager.shared.onRelease = { appState.stopDictation() }
        appState.refresh()
        // HUD may need to hide if the app relaunches mid-busy-phase (D020).
        DictationHUDController.shared.update(phase: appState.phase)
        LicenseManager.shared.refreshIfNeeded()
        if !Permissions.allGranted {
            appState.showOnboarding = true
            OnboardingWindowController.shared.show(appState: appState)
        }
    }
}
