import AppKit
import CoreGraphics

/// Places text on the clipboard, pastes via synthetic Cmd+V, then restores the
/// user's previous clipboard content.
///
/// Since the Wispr-style auto-learn decision (owner, 2026-09-08), every paste
/// also records a `Session`: the AX element and range where the text landed.
/// `CorrectionWatcher` uses that context to notice typed corrections — no
/// global watching, only the exact spot Voza touched.
enum Paster {

    /// Where a paste landed: the focused element at paste time, the exact
    /// field text and selection BEFORE the synthetic ⌘V ran. From these the
    /// watcher reconstructs the post-paste field exactly and detects typed
    /// corrections. `element == nil` → no session (auto-learn skipped).
    struct Session {
        let element: AXUIElement?
        let pastedText: String
        /// UTF-16 range (AX semantics) the paste replaced (length 0 = insertion point).
        let selectedRange: NSRange
        /// Field value at capture time (before the paste mutated it).
        let fieldBefore: String
        let startedAt: Date
    }

    private static let restoreTypes: [NSPasteboard.PasteboardType] = [
        .string, .rtf, .html, .png, .tiff, .fileURL,
    ]

    // The session is written from the paste call site (MainActor) and read by
    // the watcher's timer; a lock keeps it honest across threads.
    private static let sessionLock = NSLock()
    private static var storedSession: Session?
    static var lastSession: Session? {
        get { sessionLock.lock(); defer { sessionLock.unlock() }; return storedSession }
        set { sessionLock.lock(); defer { sessionLock.unlock() }; storedSession = newValue }
    }

    static func paste(_ text: String) {
        lastSession = captureContext(pastedText: text)
        pasteOnly(text)
    }

    /// The paste itself, without session capture (used when the caller decides
    /// the paste must not start a learning session).
    static func pasteOnly(_ text: String) {
        let pb = NSPasteboard.general
        let countBefore = pb.changeCount

        // Save first item's data so we can restore it afterwards.
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        if let first = pb.pasteboardItems?.first {
            for type in first.types where restoreTypes.contains(type) {
                if let data = first.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(80_000) // let the target app see the new pasteboard

        sendCmdV()
        usleep(250_000) // give the app time to read the pasteboard

        // Restore previous clipboard only if nothing else touched it meanwhile.
        // After our write the count is countBefore+1; a higher count means someone
        // else copied something during the paste window — leave it alone.
        if pb.changeCount == countBefore + 1 {
            pb.clearContents()
            for (type, data) in saved {
                pb.setData(data, forType: type)
            }
        }
    }

    // MARK: - AX context capture

    /// Captures the focused element + selected range at paste time. Returns
    /// nil (no session → auto-learn gracefully skipped for this paste) when
    /// Accessibility is off or the app does not expose text semantics.
    /// Captures the focused element + selected range at paste time. When
    /// Accessibility is off or the app does not expose text semantics
    /// (Electron/Chromium until forced), returns a session with `element == nil`
    /// — the watcher routes those to the late-baseline path instead of
    /// dropping auto-learn silently (D034: the Sintelia case).
    private static func captureContext(pastedText: String) -> Session {
        guard AXIsProcessTrusted(),
              let focusedEl = focusedElement() else {
            return Session(element: nil, pastedText: pastedText,
                           selectedRange: NSRange(location: 0, length: 0),
                           fieldBefore: "", startedAt: Date())
        }
        let element = focusedEl

        var rangeRef: CFTypeRef?
        var valueRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        let hasRange = rangeStatus == .success && rangeRef != nil
            && CFGetTypeID(rangeRef!) == AXValueGetTypeID()
        var selRange = CFRange()
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String
        let hasValue = valueStatus == .success && value != nil

        guard hasRange, AXValueGetValue(rangeRef as! AXValue, .cfRange, &selRange), selRange.location >= 0,
              hasValue, let fieldValue = value else {
            return Session(element: nil, pastedText: pastedText,
                           selectedRange: NSRange(location: 0, length: 0),
                           fieldBefore: "", startedAt: Date())
        }

        applyMessagingTimeout(element)
        return Session(element: element, pastedText: pastedText,
                       selectedRange: NSRange(location: selRange.location, length: selRange.length),
                       fieldBefore: fieldValue, startedAt: Date())
    }

    /// System-wide focused element, or nil when unavailable. Internal for
    /// the watcher's late-baseline reader.
    internal static var focusedElementPublic: AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        return focusedElement()
    }

    /// AX calls are synchronous IPC into the target app's main thread; if that
    /// thread is busy (a chat app streaming output, a busy Electron renderer)
    /// the caller can block for many seconds — the watcher's window dies
    /// inside one call. Cap every element we hand out at 2 s (D034: the
    /// ax=live session that never finished).
    static func applyMessagingTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 2.0)
    }

    /// Wakes the focused app's hidden accessibility support by setting the
    /// manual-override attributes on the app element. Chromium/Electron gates
    /// its web-content tree; the full web wake lives in
    /// `CorrectionWatcher.wakeAppTree` (D040, sets AXManualAccessibility on
    /// every AXWebArea — attribute-only, never VoiceOver). Returns false only
    /// when nothing stuck.
    @discardableResult
    static func forceAccessibilityOnFocusedApp() -> Bool {
        guard let element = focusedElement() else { return false }
        var pid = pid_t(0)
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return false }
        let app = AXUIElementCreateApplication(pid)
        var anySet = false
        for attr in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            let result = AXUIElementSetAttributeValue(app, attr as CFString, kCFBooleanTrue)
            if result == .success { anySet = true }
        }
        return anySet
    }

    /// System-wide focused element, or nil when unavailable.
    private static func focusedElement() -> AXUIElement? {
        let sysWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedEl = focused else { return nil }
        // P2-4 (audit 2026-09-21): a misbehaving app can hand back kCFNull or
        // an unexpected type — `as!` aborted the process. Type-check instead.
        guard CFGetTypeID(focusedEl) == AXUIElementGetTypeID() else { return nil }
        return (focusedEl as! AXUIElement)
    }

    // MARK: - Pure helpers (smoke-tested)

    /// Bounds-safe UTF-16 substring, AX-range semantics. nil when out of range.
    static func substring(_ text: String, nsRange: NSRange) -> String? {
        let ns = text as NSString
        guard nsRange.location >= 0, nsRange.length >= 0,
              nsRange.location + nsRange.length <= ns.length else { return nil }
        return ns.substring(with: nsRange)
    }

    /// Cheap character-multiset similarity in [0, 1] used to reject unrelated
    /// edits (a URL pasted over our text) while accepting small fixes
    /// (autocapitalize, one wrong word). Not a metric — a guard.
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in a { counts[c, default: 0] += 1 }
        var common = 0
        for c in b {
            if let n = counts[c], n > 0 { counts[c] = n - 1; common += 1 }
        }
        return 2.0 * Double(common) / Double(a.count + b.count)
    }

    static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // V = 9
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
    }
}
