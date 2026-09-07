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

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

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
        if !Permissions.allGranted {
            appState.showOnboarding = true
        }
    }
}
