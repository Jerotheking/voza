import AppKit
import AVFoundation
import ApplicationServices

/// Runtime permission state + helpers for the three prompts Voza needs.
enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// The global push-to-talk hotkey needs Input Monitoring. Without it the
    /// event tap silently fails — the app would look "ready" while the hotkey
    /// does nothing (P0 fix from external audit v2, §3.6).
    static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        microphoneGranted && accessibilityGranted && inputMonitoringGranted
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Opens System Settings → Privacy → Accessibility. The OS shows the prompt
    /// on first AX API use; this deep link lets users grant it later.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
