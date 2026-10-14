import XCTest
@testable import VozaKit

@MainActor
final class HotKeyManagerTests: XCTestCase {
    // V03-AC01: Ground-truth keycodes match Apple HIToolbox Events.h (0x3D Right Option,
    // 0x3E Right Control, 0x3A Left Option, 0x36 Right Command).
    func testKeyCodeGroundTruthConstants() {
        XCTAssertEqual(VozaKeyCodes.rightOption, 0x3D)
        XCTAssertEqual(VozaKeyCodes.leftOption, 0x3A)
        XCTAssertEqual(VozaKeyCodes.rightControl, 0x3E)
        XCTAssertEqual(VozaKeyCodes.leftControl, 0x3B)
        XCTAssertEqual(VozaKeyCodes.rightCommand, 0x36)
        XCTAssertNotEqual(VozaKeyCodes.rightOption, 0x3A, "0x3A is Left Option, never Right Option")
        XCTAssertNotEqual(VozaKeyCodes.rightControl, 0x36, "0x36 is Right Command, never Right Control")
        XCTAssertEqual(VozaKeyCodes.legacyCleanup, 0x3E)
        XCTAssertEqual(VozaKeyCodes.dictation, [0x3D, 0x3A])
    }

    // V03-AC02: Sequence pressA -> pressB -> releaseB -> releaseA only starts once on A
    // and only releases when owner A is released.
    func testOwnerKeyIsolationAcrossBothOptionKeys() {
        let mgr = HotKeyManager(tapInstaller: {})
        var presses = 0
        var releases = 0
        mgr.onPressNormal = { presses += 1 }
        mgr.onRelease = { releases += 1 }

        // 1. Press Right Option (A = 0x3D)
        let t1 = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask
        )
        XCTAssertEqual(t1, .started(ownerKeyCode: 0x3D))
        XCTAssertEqual(mgr.activeOwnerKeyCode, 0x3D)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 0)

        // 2. Press Left Option (B = 0x3A) while Right Option is still held
        let t2 = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.leftOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask | VozaKeyCodes.deviceLeftOptionMask
        )
        XCTAssertEqual(t2, .ignoredBusy(activeOwnerKeyCode: 0x3D, ignoredKeyCode: 0x3A))
        XCTAssertEqual(mgr.activeOwnerKeyCode, 0x3D)
        XCTAssertEqual(presses, 1, "Second Option key must not start a second dictation")
        XCTAssertEqual(releases, 0)

        // 3. Release Left Option (B = 0x3A) while Right Option (0x3D) remains held
        let t3 = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.leftOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask
        )
        XCTAssertEqual(t3, .ignoredBusy(activeOwnerKeyCode: 0x3D, ignoredKeyCode: 0x3A))
        XCTAssertEqual(mgr.activeOwnerKeyCode, 0x3D, "Releasing non-owner Option must not end owner session")
        XCTAssertEqual(releases, 0)

        // 4. Release Right Option (owner A = 0x3D) -> ends session
        let t4 = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: false, ctrl: false, cmd: false, shift: false,
            rawFlags: 0
        )
        XCTAssertEqual(t4, .released(ownerKeyCode: 0x3D))
        XCTAssertNil(mgr.activeOwnerKeyCode)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    // V03-AC02: Releasing owner A while B is still held still ends A's session when device flags report A up.
    func testReleasingOwnerWhileSecondKeyStillHeldReleasesSession() {
        let mgr = HotKeyManager(tapInstaller: {})
        var presses = 0
        var releases = 0
        mgr.onPressNormal = { presses += 1 }
        mgr.onRelease = { releases += 1 }

        _ = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask
        )
        _ = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.leftOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask | VozaKeyCodes.deviceLeftOptionMask
        )
        // Release Right Option (owner 0x3D) while Left Option (0x3A) is still held (alt remains true)
        let t3 = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceLeftOptionMask
        )
        XCTAssertEqual(t3, .released(ownerKeyCode: 0x3D))
        XCTAssertNil(mgr.activeOwnerKeyCode)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    // V03-AC03: pressA -> tapDisabled -> releaseA resets latch on disable and does not double-fire on releaseA.
    func testTapDisabledResetsLatchedKeyAndNotifiesReleaseOnce() {
        let mgr = HotKeyManager(tapInstaller: {})
        var presses = 0
        var releases = 0
        mgr.onPressNormal = { presses += 1 }
        mgr.onRelease = { releases += 1 }

        _ = mgr.processFlagsChanged(keyCode: VozaKeyCodes.rightOption, alt: true, ctrl: false, cmd: false, shift: false)
        XCTAssertEqual(mgr.activeOwnerKeyCode, 0x3D)
        XCTAssertEqual(presses, 1)

        let disabledTransition = mgr.handleTapDisabled(byTimeout: true)
        XCTAssertEqual(disabledTransition, .cancelled(previousOwnerKeyCode: 0x3D))
        XCTAssertNil(mgr.activeOwnerKeyCode, "Tap disable must unlatch active key")
        XCTAssertEqual(releases, 1, "Active session must be released cleanly when tap dies")

        // Subsequent key-up after tap recovery must not fire a second release
        let lateUp = mgr.processFlagsChanged(keyCode: VozaKeyCodes.rightOption, alt: false, ctrl: false, cmd: false, shift: false)
        XCTAssertEqual(lateUp, .none)
        XCTAssertEqual(releases, 1)
    }

    // V03-AC03: press -> repeat -> stop is idempotent and clears latch.
    func testPressRepeatStopIsIdempotent() {
        let mgr = HotKeyManager(tapInstaller: {})
        var presses = 0
        var releases = 0
        mgr.onPressNormal = { presses += 1 }
        mgr.onRelease = { releases += 1 }

        _ = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask
        )
        // Duplicate/repeat down event on same owner key
        let repeatTransition = mgr.processFlagsChanged(
            keyCode: VozaKeyCodes.rightOption,
            alt: true, ctrl: false, cmd: false, shift: false,
            rawFlags: VozaKeyCodes.deviceRightOptionMask
        )
        XCTAssertEqual(repeatTransition, .none)
        XCTAssertEqual(presses, 1)

        mgr.stop()
        XCTAssertNil(mgr.activeOwnerKeyCode)
        XCTAssertEqual(releases, 1)

        // Second stop() is a no-op
        mgr.stop()
        XCTAssertEqual(releases, 1)
    }

    // pstack blast-radius: releasing ⌥ after a chord shortcut (e.g. ⌥⌘C) never fires spurious onRelease.
    func testChordShortcutNeverFiresPressOrSpuriousRelease() {
        let mgr = HotKeyManager(tapInstaller: {})
        var presses = 0
        var releases = 0
        mgr.onPressNormal = { presses += 1 }
        mgr.onRelease = { releases += 1 }

        let down = mgr.processFlagsChanged(keyCode: VozaKeyCodes.rightOption, alt: true, ctrl: false, cmd: true, shift: false)
        XCTAssertEqual(down, .none)
        let up = mgr.processFlagsChanged(keyCode: VozaKeyCodes.rightOption, alt: false, ctrl: false, cmd: true, shift: false)
        XCTAssertEqual(up, .none)
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(releases, 0, "Chord shortcut release must never trigger onRelease")
    }
}
