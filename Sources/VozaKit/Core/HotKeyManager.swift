import AppKit
import CoreGraphics

/// Global push-to-talk hotkeys via CGEventTap.
/// Hold Option (either side) → normal dictation; hold Right ⌘ → cleanup.
///
/// KEYCODE GROUND TRUTH (verified against Apple's HIToolbox Events.h, SDK 15.2):
/// kVK_Option=0x3A(58, LEFT), kVK_RightOption=0x3D(61), kVK_Control=0x3B(59, LEFT),
/// kVK_RightCommand=0x36(54), kVK_RightControl=0x3E(62).
/// HARDWARE CONSTRAINT (owner QA 2026-09-08, MacBook Pro M4): laptops have NO
/// right Control — the bottom row is fn ⌃ ⌥ ⌘ [space] ⌘ ⌥. Cleanup therefore
/// binds to Right ⌘ (0x36), which exists on every Mac and has no system function
/// when held alone. Left ⌘/⌃/⌥ remain untouched for real shortcuts.
enum VozaKeyCodes {
    /// Right Option only (owner decision 2026-09-08): ONE dedicated physical
    /// key for dictation — no ambiguity, no ergonomic split. Left Option
    /// remains free for real Option shortcuts.
    static let dictation: Set<Int64> = [0x3D] // kVK_RightOption
    /// Right ⌘ only — exists on 100% of Macs (laptops lack right Control).
    static let cleanup: Int64 = 0x36 // kVK_RightCommand
}
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressNormal: (@MainActor () -> Void)?
    var onPressCleanup: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var normalDown = false
    private var cleanupDown = false

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
        let cmd = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                shared.handleFlagsChanged(keyCode: keyCode, alt: alt, ctrl: ctrl, cmd: cmd, shift: shift)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    @MainActor private func handleFlagsChanged(keyCode: Int64, alt: Bool, ctrl: Bool, cmd: Bool, shift: Bool) {
        let isDictationKey = VozaKeyCodes.dictation.contains(keyCode)
        let isCleanupKey = keyCode == VozaKeyCodes.cleanup

        if isDictationKey {
            // Fire only as a BARE modifier: if ⌃/⌘/⇧ is already held, this is
            // a real shortcut (⌥⇧…, ⌥⌘…) — never hijack it for dictation.
            if alt && !ctrl && !cmd && !shift && !normalDown {
                normalDown = true
                onPressNormal?()
            } else if !alt {
                normalDown = false
            }
        }
        if isCleanupKey {
            // Right ⌘ raises .maskCommand (not .maskControl) — the flag must
            // match the physical key we bound, or the press never fires.
            // Same bare-modifier rule: ⌃/⌥/⇧ already held → it's a shortcut.
            if cmd && !ctrl && !alt && !shift && !cleanupDown {
                cleanupDown = true
                onPressCleanup?()
            } else if !cmd {
                cleanupDown = false
            }
        }
        // Stop only when NO hotkey is held anymore: pressing the other hotkey
        // mid-recording must not cut the current dictation short.
        if (isDictationKey || isCleanupKey) && !normalDown && !cleanupDown {
            onRelease?()
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
