import SwiftUI

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
        case .cleaning:
            Image(systemName: "sparkles")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKeyManager.shared.start()
        TranscriptStore.shared.loadRecent(limit: 10)

        // Wire push-to-talk to the shared AppState.
        let appState = AppState.shared
        HotKeyManager.shared.onPressNormal = { appState.startDictation(cleanup: false) }
        HotKeyManager.shared.onPressCleanup = { appState.startDictation(cleanup: true) }
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
