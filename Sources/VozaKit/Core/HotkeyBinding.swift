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

/// Configurable activation style prepared for V18 (hold vs toggle) without altering D032 defaults.
enum HotkeyActivationStyle: String, Codable, Equatable, Sendable {
    case hold
    case toggle
}

struct HotkeyBinding: Codable, Equatable, Sendable {
    var keyCodes: Set<Int64>
    var style: HotkeyActivationStyle

    static let defaultDictation = HotkeyBinding(
        keyCodes: VozaKeyCodes.dictation,
        style: .hold
    )
}

/// Pure, deterministic state machine for push-to-talk session ownership (V03 / D057 pstack).
///
/// Invariants (`make-illegal-states-unrepresentable`):
/// 1. Only a bare modifier press (`alt && !ctrl && !cmd && !shift`) when idle can claim `activeOwnerKeyCode`.
/// 2. While `activeOwnerKeyCode` is non-nil, pressing or releasing the opposite Option key returns
///    `.ignoredBusy` and NEVER starts a second session or releases the owner's session (V03-AC02).
/// 3. Releasing a chord shortcut (`⌥⌘C`) when `activeOwnerKeyCode == nil` returns `.none` and NEVER
///    emits a spurious `.released` transition.
/// 4. Losing the event tap (`tapDisabled`) or calling `stop()` resets all latches and returns
///    `.cancelled(previousOwnerKeyCode:)` if a session was active (V03-AC03).
struct HotkeySessionReducer: Equatable, Sendable {
    enum Transition: Equatable, Sendable {
        case none
        case started(ownerKeyCode: Int64)
        case released(ownerKeyCode: Int64)
        case ignoredBusy(activeOwnerKeyCode: Int64, ignoredKeyCode: Int64)
        case cancelled(previousOwnerKeyCode: Int64?)
    }

    private(set) var activeOwnerKeyCode: Int64?
    private(set) var heldKeys: Set<Int64> = []
    let allowedKeyCodes: Set<Int64>

    init(allowedKeyCodes: Set<Int64> = VozaKeyCodes.dictation) {
        self.allowedKeyCodes = allowedKeyCodes
    }

    mutating func handleFlagsChanged(
        keyCode: Int64,
        alt: Bool,
        ctrl: Bool,
        cmd: Bool,
        shift: Bool,
        rawFlags: UInt64 = 0,
        explicitIsDown: Bool? = nil
    ) -> Transition {
        guard allowedKeyCodes.contains(keyCode) else {
            if !alt, let owner = activeOwnerKeyCode {
                heldKeys.removeAll()
                activeOwnerKeyCode = nil
                return .released(ownerKeyCode: owner)
            }
            if !alt {
                heldKeys.removeAll()
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
            // Fallback when synthetic events omit device-side bits:
            // if keyCode is not yet in heldKeys, this flagsChanged is a press;
            // if keyCode IS in heldKeys while another key is also held and alt stays true,
            // this flagsChanged for keyCode represents keyCode being released.
            if !heldKeys.contains(keyCode) {
                isDown = true
            } else if heldKeys.count > 1 {
                isDown = false
            } else {
                // Single held key receiving a duplicate down/repeat event while alt is true
                isDown = true
            }
        }

        if isDown {
            let alreadyHeld = !heldKeys.insert(keyCode).inserted
            if let owner = activeOwnerKeyCode {
                if owner == keyCode && alreadyHeld {
                    // Key repeat on the active owner key is a no-op
                    return .none
                }
                return .ignoredBusy(activeOwnerKeyCode: owner, ignoredKeyCode: keyCode)
            }
            // Bare modifier check: never hijack ⌥+⌃/⌘/⇧ shortcuts
            guard alt && !ctrl && !cmd && !shift else {
                return .none
            }
            activeOwnerKeyCode = keyCode
            return .started(ownerKeyCode: keyCode)
        } else {
            heldKeys.remove(keyCode)
            if !alt {
                heldKeys.removeAll()
            }
            guard let owner = activeOwnerKeyCode else {
                return .none
            }
            if owner == keyCode || !alt {
                activeOwnerKeyCode = nil
                return .released(ownerKeyCode: owner)
            }
            return .ignoredBusy(activeOwnerKeyCode: owner, ignoredKeyCode: keyCode)
        }
    }

    mutating func reset() -> Transition {
        let prev = activeOwnerKeyCode
        activeOwnerKeyCode = nil
        heldKeys.removeAll()
        return .cancelled(previousOwnerKeyCode: prev)
    }
}
