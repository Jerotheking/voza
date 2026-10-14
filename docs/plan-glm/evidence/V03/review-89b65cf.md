# V03 Evidence & pstack Review (89b65cf)

- **Ticket:** V03 — Corregir atajos y modelar la tecla dueña de la sesión
- **Base Commit / Code Revision:** `89b65cffc0f247d9670c4a32c3a16c4f4a47057f`
- **Methodology:** `pstack` (`poteto-mode`: `/interrogate`, `/blast-radius`, `/correct`, `/no-comments`, `prove-it-works`) + `/opencode` review workflow (`D057`).

## Acceptance Criteria Verification

| AC | Kind | Status | Evidence |
|---|---|---|---|
| `V03-AC01` | automated | PASS | `VozaKeyCodes` in `Sources/VozaKit/Core/HotkeyBinding.swift` pins `rightOption = 0x3D` (`kVK_RightOption`), `leftOption = 0x3A` (`kVK_Option`), `rightControl = 0x3E` (`kVK_RightControl`), `rightCommand = 0x36` (`kVK_RightCommand`), `legacyCleanup = 0x3E`. Verified by `HotKeyManagerTests.testKeyCodeGroundTruthConstants` and `VozaSmoke` (`[PASS] v03 ac01 rightOption=0x3D leftOption=0x3A`). |
| `V03-AC02` | automated | PASS | `HotkeySessionReducer` tracks `activeOwnerKeyCode: Int64?` and `heldKeys: Set<Int64>` using `IOKit/IOLLEvent.h` device-side masks (`0x40` Right Option, `0x20` Left Option). Sequence `pressA(0x3D) -> pressB(0x3A) -> releaseB(0x3A) -> releaseA(0x3D)` emits `.started(0x3D)`, `.ignoredBusy`, `.ignoredBusy`, `.released(0x3D)`. Verified by `HotKeyManagerTests.testOwnerKeyIsolationAcrossBothOptionKeys` and `VozaSmoke` (`[PASS] v03 ac02 pressA->pressB->releaseB->releaseA owner isolation`). |
| `V03-AC03` | automated | PASS | `HotKeyManager` handles `.tapDisabledByTimeout` and `.tapDisabledByUserInput`, invalidates `CFRunLoopSource` and `watchdog` on `stop()`, ignores key-repeats on the owner key, and resets latched state via `reducer.reset()`. Verified by `HotKeyManagerTests` and `VozaSmoke` (`[PASS] v03 ac03 repeat ignored + tapDisabled/stop unlatches cleanly`). |
| `V03-AC04` | manual | PASS | Physical keyboard QA verified on owner Mac (`macOS`, Apple Silicon, internal & external keyboard) across `V01`/`D021`/`D032` and preserved under `D057` (`0x3D` and `0x3A` bare-modifier hold-to-talk, chord shortcuts `⌥⌘…` ignored without spurious release). |
| `V03-AC05` | inspection | PASS | `HotKeyManager.installTap()` subscribes exclusively to `1 << CGEventType.flagsChanged.rawValue` with `.listenOnly` option and never inspects or logs character keystrokes. |
