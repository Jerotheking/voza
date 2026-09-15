import AppKit
import CoreGraphics

/// Global push-to-talk hotkeys via CGEventTap.
/// Hold Option (either side) → dictation; release → paste (D032).
///
/// KEYCODE GROUND TRUTH (verified against Apple's HIToolbox Events.h, SDK 15.2):
/// kVK_Option=0x3A(58, LEFT), kVK_RightOption=0x3D(61).
///
/// BINDING HISTORY: a second "cleanup" hotkey lived on Right ⌘, then LEFT
/// Option (D021), until D032 (2026-09-15) removed the cleanup mode entirely —
/// the owner measured that local-LLM polish could not win the latency war
/// (D027-D031 guards kept tripping on a real machine). The owner's stated
/// end-state — ONE behavior, ONE button — is now literal: both Options do
/// the same thing, so muscle memory built on either key keeps working.
/// Bare-modifier rule preserved: ⌥ held together with ⌃/⌘/⇧ is a real
/// shortcut and never starts a dictation.
enum VozaKeyCodes {
    /// Both Option keys (D032): one behavior, no mode ambiguity.
    static let dictation: Set<Int64> = [0x3D, 0x3A] // kVK_RightOption, kVK_Option (LEFT)
}
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressNormal: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var normalDown = false

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

    /// Creates or re-enables the event tap on demand. Internal so the
    /// onboarding's Input Monitoring step can trigger the OS prompt at the
    /// moment the user clicks (rather than on their first dictation attempt).
    func ensureTapAlive() {
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

        if isDictationKey {
            // Fire only as a BARE modifier: if ⌃/⌘/⇧ is already held, this is
            // a real shortcut (⌥⇧…, ⌥⌘…) — never hijack it for dictation.
            if alt && !ctrl && !cmd && !shift && !normalDown {
                normalDown = true
                onPressNormal?()
            } else if !alt {
                normalDown = false
            }
            // Stop only when no hotkey is held anymore.
            if !normalDown {
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
    }
}
