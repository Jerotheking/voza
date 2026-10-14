import AppKit
import CoreGraphics

/// Global push-to-talk hotkeys via CGEventTap (V03 / D032 / D057).
/// Hold Option (either side, 0x3D Right or 0x3A Left) -> dictation; release owner key -> paste.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressNormal: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var reducer = HotkeySessionReducer()

    /// True while a dictation key owns an active push-to-talk session.
    var normalDown: Bool { reducer.activeOwnerKeyCode != nil }
    /// The keyCode (`0x3D` or `0x3A`) that started the current session, if any.
    var activeOwnerKeyCode: Int64? { reducer.activeOwnerKeyCode }

    /// Watchdog that resurrects a dead tap. Invalidated on `stop()` so stopped
    /// instances never resurrect their tap in the background (V03-AC03).
    private(set) var watchdog: Timer?

    /// Installation seam (hermetic tests inject a counting no-op; never
    /// create real event taps from a test process).
    var tapInstaller: () -> Void

    init(tapInstaller: (() -> Void)? = nil) {
        self.tapInstaller = tapInstaller ?? {}
        if tapInstaller == nil {
            self.tapInstaller = { [weak self] in self?.installTap() }
        }
    }

    func start() {
        tapInstaller()
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.ensureTapAlive()
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func installTap() {
        tearDownTap()
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, _ -> Unmanaged<CGEvent>? in
                HotKeyManager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        ) else {
            tapActive = false
            lastTapError = L.t("Global hotkey unavailable — grant Input Monitoring",
                               es: "Hotkey global no disponible — otorga Input Monitoring")
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapActive = true
        lastTapError = nil
    }

    private func tearDownTap() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            CFRunLoopSourceInvalidate(src)
            runLoopSource = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    private(set) var tapActive = false
    private(set) var lastTapError: String?

    func ensureTapAlive() {
        guard let tap else {
            tapInstaller()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            let transition = reducer.reset()
            if case .cancelled(let previousOwner) = transition, previousOwner != nil {
                Task { @MainActor [weak self] in self?.onRelease?() }
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            tapActive = CGEvent.tapIsEnabled(tap: tap)
        }
    }

    private static func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let byTimeout = (type == .tapDisabledByTimeout)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = shared.handleTapDisabled(byTimeout: byTimeout)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rawFlags = event.flags.rawValue
        let alt = event.flags.contains(.maskAlternate)
        let ctrl = event.flags.contains(.maskControl)
        let cmd = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = shared.processFlagsChanged(
                    keyCode: keyCode,
                    alt: alt,
                    ctrl: ctrl,
                    cmd: cmd,
                    shift: shift,
                    rawFlags: rawFlags
                )
            }
        }
        return Unmanaged.passUnretained(event)
    }

    @MainActor
    @discardableResult
    func processFlagsChanged(
        keyCode: Int64,
        alt: Bool,
        ctrl: Bool,
        cmd: Bool,
        shift: Bool,
        rawFlags: UInt64 = 0,
        explicitIsDown: Bool? = nil
    ) -> HotkeySessionReducer.Transition {
        let transition = reducer.handleFlagsChanged(
            keyCode: keyCode,
            alt: alt,
            ctrl: ctrl,
            cmd: cmd,
            shift: shift,
            rawFlags: rawFlags,
            explicitIsDown: explicitIsDown
        )
        switch transition {
        case .started:
            onPressNormal?()
        case .released:
            onRelease?()
        case .none, .ignoredBusy, .cancelled:
            break
        }
        return transition
    }

    @MainActor
    @discardableResult
    func handleTapDisabled(byTimeout: Bool) -> HotkeySessionReducer.Transition {
        let transition = reducer.reset()
        if case .cancelled(let previousOwner) = transition, previousOwner != nil {
            onRelease?()
        }
        if byTimeout, let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            tapActive = CGEvent.tapIsEnabled(tap: tap)
        } else {
            tapActive = false
        }
        return transition
    }

    @MainActor
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        tearDownTap()
        tapActive = false
        let transition = reducer.reset()
        if case .cancelled(let previousOwner) = transition, previousOwner != nil {
            onRelease?()
        }
    }
}
