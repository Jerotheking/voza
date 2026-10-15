import CoreGraphics
import Foundation

/// Ground-truth virtual keycodes verified against Apple's HIToolbox/Events.h (macOS SDK 15.2)
/// and hardware device-dependent modifier masks from IOKit/hidsystem/IOLLEvent.h (V03-AC01).
enum VozaKeyCodes {
    static let rightOption: Int64  = 0x3D // 61 — kVK_RightOption
    static let leftOption: Int64   = 0x3A // 58 — kVK_Option (Left)
    static let rightControl: Int64 = 0x3E // 62 — kVK_RightControl
    static let leftControl: Int64  = 0x3B // 59 — kVK_Control (Left)
    static let rightCommand: Int64 = 0x36 // 54 — kVK_RightCommand (never announce as Right Control)
    static let leftCommand: Int64  = 0x37 // 55 — kVK_Command (Left)
    static let escape: Int64       = 0x35 // 53 — kVK_Escape

    /// Both Option keys trigger dictation (D032: one behavior, no mode ambiguity).
    static let dictation: Set<Int64> = [rightOption, leftOption]

    /// Legacy cleanup keycode kept as an explicit constant for V03-AC01 verification.
    static let legacyCleanup: Int64 = rightControl

    // Device-dependent lower-16-bit CGEventFlags masks (IOKit/hidsystem/IOLLEvent.h)
    static let deviceLeftControlMask: UInt64  = 0x0000_0001 // NX_DEVICELCTLKEYMASK
    static let deviceLeftOptionMask: UInt64   = 0x0000_0020 // NX_DEVICELALTKEYMASK
    static let deviceRightOptionMask: UInt64  = 0x0000_0040 // NX_DEVICERALTKEYMASK
    static let deviceRightControlMask: UInt64 = 0x0000_2000 // NX_DEVICERCTLKEYMASK
    static let deviceAnyOptionMask: UInt64    = deviceLeftOptionMask | deviceRightOptionMask

    /// Resolves whether a specific Option key (`0x3D` or `0x3A`) is physically down
    /// when device-dependent flags are present on `CGEventFlags`. Returns `nil` when
    /// the event carries only aggregate `maskAlternate` without side-specific bits.
    static func isOptionSideDown(keyCode: Int64, rawFlags: UInt64, altAggregate: Bool) -> Bool? {
        guard altAggregate else { return false }
        guard (rawFlags & deviceAnyOptionMask) != 0 else { return nil }
        switch keyCode {
        case rightOption:
            return (rawFlags & deviceRightOptionMask) != 0
        case leftOption:
            return (rawFlags & deviceLeftOptionMask) != 0
        default:
            return nil
        }
    }
}

/// Configurable activation style prepared for V18/D064 (hold, toggle, or hybrid tap+hold).
enum HotkeyActivationStyle: String, Codable, Equatable, Sendable {
    case hold
    case toggle
    case hybrid
}

struct HotkeyBinding: Codable, Equatable, Sendable {
    var keyCodes: Set<Int64>
    var style: HotkeyActivationStyle

    static let defaultDictation = HotkeyBinding(
        keyCodes: VozaKeyCodes.dictation,
        style: .hybrid
    )
}

/// Pure, deterministic state machine for push-to-talk + tap-to-toggle session ownership (V03 / D057 / D064 pstack).
///
/// Invariants (`make-illegal-states-unrepresentable`):
/// 1. Only a bare modifier press (`alt && !ctrl && !cmd && !shift`) when idle can claim `activeOwnerKeyCode`.
/// 2. While `activeOwnerKeyCode` is non-nil in hold mode, pressing or releasing the opposite Option key returns
///    `.ignoredBusy` and NEVER starts a second session or releases the owner's session (V03-AC02).
/// 3. Hybrid Tap-to-Toggle + Hold-to-Talk (`D064`):
///    - If the owner key is released within `< tapMaxDuration` (`0.28s`) when `uptimeSeconds` is provided,
///      the session latches into hands-free mode (`isLatchedHandsFree = true`) and emits `.latched(ownerKeyCode:)`.
///    - If the owner key is held for `>= tapMaxDuration` (or `uptimeSeconds == nil`), releasing it emits
///      `.released(ownerKeyCode:)` (classic push-to-talk).
///    - While `isLatchedHandsFree == true`, pressing any allowed Option key immediately finishes the session
///      (`.released(ownerKeyCode:)`) and absorbs that key's subsequent release via `awaitingStopReleaseKeyCode`.
/// 4. If another modifier (`ctrl`, `cmd`, `shift`) or any regular key (`handleNonModifierKeyDown`) is pressed
///    while holding Option, the embryonic session is cancelled (`.cancelled`) so shortcuts (`⌥⌘C`, `⌥+n`, `⌥+⌫`)
///    never latch hands-free or transcribe.
/// 5. Losing the event tap (`tapDisabled`) or calling `stop()` resets all latches and returns
///    `.cancelled(previousOwnerKeyCode:)` if a session was active (V03-AC03).
struct HotkeySessionReducer: Equatable, Sendable {
    /// Maximum press duration (in seconds) that counts as a quick tap to latch hands-free mode.
    static let defaultTapMaxDuration: TimeInterval = 0.28

    enum Transition: Equatable, Sendable {
        case none
        case started(ownerKeyCode: Int64)
        case latched(ownerKeyCode: Int64)
        case released(ownerKeyCode: Int64)
        case ignoredBusy(activeOwnerKeyCode: Int64, ignoredKeyCode: Int64)
        case cancelled(previousOwnerKeyCode: Int64?)
    }

    private(set) var activeOwnerKeyCode: Int64?
    private(set) var isLatchedHandsFree: Bool = false
    private var pressedAtUptime: TimeInterval?
    private var awaitingStopReleaseKeyCode: Int64?
    private(set) var heldKeys: Set<Int64> = []
    let allowedKeyCodes: Set<Int64>
    let tapMaxDuration: TimeInterval

    init(
        allowedKeyCodes: Set<Int64> = VozaKeyCodes.dictation,
        tapMaxDuration: TimeInterval = HotkeySessionReducer.defaultTapMaxDuration
    ) {
        self.allowedKeyCodes = allowedKeyCodes
        self.tapMaxDuration = tapMaxDuration
    }

    mutating func handleFlagsChanged(
        keyCode: Int64,
        alt: Bool,
        ctrl: Bool,
        cmd: Bool,
        shift: Bool,
        rawFlags: UInt64 = 0,
        explicitIsDown: Bool? = nil,
        uptimeSeconds: TimeInterval? = nil
    ) -> Transition {
        guard allowedKeyCodes.contains(keyCode) else {
            // If another modifier key is pressed during the initial tap window (< tapMaxDuration),
            // treat it as a keyboard shortcut chord (e.g. ⌥⌘V) and cancel the embryonic dictation.
            if (ctrl || cmd || shift),
               let owner = activeOwnerKeyCode,
               !isLatchedHandsFree,
               let startUptime = pressedAtUptime,
               let nowUptime = uptimeSeconds,
               (nowUptime - startUptime) < tapMaxDuration {
                activeOwnerKeyCode = nil
                pressedAtUptime = nil
                return .cancelled(previousOwnerKeyCode: owner)
            }
            if !alt, let owner = activeOwnerKeyCode, !isLatchedHandsFree {
                heldKeys.removeAll()
                activeOwnerKeyCode = nil
                pressedAtUptime = nil
                return .released(ownerKeyCode: owner)
            }
            if !alt {
                heldKeys.removeAll()
                awaitingStopReleaseKeyCode = nil
            }
            return .none
        }

        let isDown: Bool
        if let explicitIsDown {
            isDown = alt ? explicitIsDown : false
        } else if let sideDown = VozaKeyCodes.isOptionSideDown(keyCode: keyCode, rawFlags: rawFlags, altAggregate: alt) {
            isDown = sideDown
        } else if !alt {
            isDown = false
        } else {
            if !heldKeys.contains(keyCode) {
                isDown = true
            } else if heldKeys.count > 1 {
                isDown = false
            } else {
                isDown = true
            }
        }

        if isDown {
            let alreadyHeld = !heldKeys.insert(keyCode).inserted

            // If we are waiting for the release of the key that stopped a hands-free session, ignore repeats.
            if awaitingStopReleaseKeyCode == keyCode && alreadyHeld {
                return .none
            }

            if let owner = activeOwnerKeyCode {
                // D064: In hands-free latched mode, pressing Option again finishes the dictation!
                if isLatchedHandsFree {
                    activeOwnerKeyCode = nil
                    isLatchedHandsFree = false
                    pressedAtUptime = nil
                    awaitingStopReleaseKeyCode = keyCode
                    return .released(ownerKeyCode: owner)
                }
                if owner == keyCode && alreadyHeld {
                    return .none
                }
                return .ignoredBusy(activeOwnerKeyCode: owner, ignoredKeyCode: keyCode)
            }

            // Bare modifier check: never hijack ⌥+⌃/⌘/⇧ shortcuts
            guard alt && !ctrl && !cmd && !shift else {
                return .none
            }
            activeOwnerKeyCode = keyCode
            isLatchedHandsFree = false
            pressedAtUptime = uptimeSeconds
            awaitingStopReleaseKeyCode = nil
            return .started(ownerKeyCode: keyCode)
        } else {
            heldKeys.remove(keyCode)
            if !alt {
                heldKeys.removeAll()
            }

            // Absorb the key-up of the tap that stopped a hands-free session.
            if let stopKey = awaitingStopReleaseKeyCode, (stopKey == keyCode || !alt) {
                awaitingStopReleaseKeyCode = nil
                return .none
            }

            guard let owner = activeOwnerKeyCode else {
                return .none
            }

            if isLatchedHandsFree {
                return .none
            }

            if owner == keyCode || !alt {
                // D064: Quick tap (< tapMaxDuration) with no chord modifier latches hands-free mode!
                if !ctrl && !cmd && !shift,
                   let startUptime = pressedAtUptime,
                   let nowUptime = uptimeSeconds,
                   nowUptime >= startUptime,
                   (nowUptime - startUptime) < tapMaxDuration {
                    isLatchedHandsFree = true
                    pressedAtUptime = nil
                    return .latched(ownerKeyCode: owner)
                }
                activeOwnerKeyCode = nil
                isLatchedHandsFree = false
                pressedAtUptime = nil
                return .released(ownerKeyCode: owner)
            }
            return .ignoredBusy(activeOwnerKeyCode: owner, ignoredKeyCode: keyCode)
        }
    }

    /// Handles a non-modifier `.keyDown` observed by the `.listenOnly` event tap (`D064` blast-radius guard):
    /// - If the user presses any regular key while holding Option (`!isLatchedHandsFree`), it is an Option-shortcut
    ///   (e.g. `⌥+n` for `ñ`, `⌥+⌫` delete word, `⌥+←` jump word) — cancel the embryonic session immediately so it
    ///   never latches hands-free or transcribes.
    /// - If `isLatchedHandsFree == true` and the user presses `Escape` (`0x35`), cancel the hands-free session.
    mutating func handleNonModifierKeyDown(keyCode: Int64) -> Transition {
        guard let owner = activeOwnerKeyCode else { return .none }
        if !isLatchedHandsFree || keyCode == VozaKeyCodes.escape {
            activeOwnerKeyCode = nil
            isLatchedHandsFree = false
            pressedAtUptime = nil
            // Keep awaitingStopReleaseKeyCode = owner if Option is still physically held so its release is absorbed!
            if heldKeys.contains(owner) {
                awaitingStopReleaseKeyCode = owner
            }
            return .cancelled(previousOwnerKeyCode: owner)
        }
        return .none
    }

    mutating func reset() -> Transition {
        let prev = activeOwnerKeyCode
        activeOwnerKeyCode = nil
        isLatchedHandsFree = false
        pressedAtUptime = nil
        awaitingStopReleaseKeyCode = nil
        heldKeys.removeAll()
        return .cancelled(previousOwnerKeyCode: prev)
    }
}
