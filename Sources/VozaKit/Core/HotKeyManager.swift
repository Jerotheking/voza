import AppKit
import CoreGraphics

/// Global push-to-talk hotkeys via CGEventTap.
/// Default: hold Right Option (keycode 58) → normal dictation,
/// hold Right Control (keycode 54) → dictation with AI cleanup.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressNormal: (@MainActor () -> Void)?
    var onPressCleanup: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var normalDown = false
    private var cleanupDown = false
    private let normalKeyCode: Int64 = 58  // Right Option
    private let cleanupKeyCode: Int64 = 54 // Right Control

    func start() {
        installTap()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.ensureTapAlive()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func installTap() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                HotKeyManager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        ) else {
            // Tap creation failed (usually missing Input Monitoring). Expose it
            // instead of failing silently — "ready" must never be a lie (audit v2 §3.6).
            tapActive = false
            lastTapError = L.t("Global hotkey unavailable — grant Input Monitoring",
                               es: "Hotkey global no disponible — otorga Input Monitoring")
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapActive = true
        lastTapError = nil
    }

    /// True when the event tap was created and enabled. The watchdog retries
    /// periodically, so this can flip back to true without relaunching.
    private(set) var tapActive = false
    /// Human-readable reason the tap is not active, for the Status home.
    private(set) var lastTapError: String?

    private func ensureTapAlive() {
        guard let tap else {
            installTap()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private static func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Listen-only tap: we never modify or swallow events, so hand them back
        // unretained. passRetained here would leak one CGEvent per keystroke.
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let alt = event.flags.contains(.maskAlternate)
        let ctrl = event.flags.contains(.maskControl)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                shared.handleFlagsChanged(keyCode: keyCode, alt: alt, ctrl: ctrl)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    @MainActor private func handleFlagsChanged(keyCode: Int64, alt: Bool, ctrl: Bool) {
        if keyCode == normalKeyCode {
            if alt && !normalDown {
                normalDown = true
                onPressNormal?()
            } else if !alt && normalDown {
                normalDown = false
                onRelease?()
            }
        }
        if keyCode == cleanupKeyCode {
            if ctrl && !cleanupDown {
                cleanupDown = true
                onPressCleanup?()
            } else if !ctrl && cleanupDown {
                cleanupDown = false
                onRelease?()
            }
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        normalDown = false
        cleanupDown = false
    }
}
