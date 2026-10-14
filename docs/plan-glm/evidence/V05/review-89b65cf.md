# V05 Evidence & pstack Review (89b65cf)

- **Ticket:** V05 — Asegurar captura, escritura WAV y cleanup de recursos
- **Base Commit / Code Revision:** `89b65cffc0f247d9670c4a32c3a16c4f4a47057f`
- **Methodology:** `pstack` (`poteto-mode`) + `/opencode` (`D059`).

## Acceptance Criteria Verification

| AC | Kind | Status | Evidence |
|---|---|---|---|
| `V05-AC01` | automated | PASS | `AudioAsset.inspectWAV(at:)` in `Sources/VozaKit/Core/AudioAsset.swift` verifies 44-byte header, `fmt = 3` (IEEE Float32), `channels = 1`, `sampleRate = 16000`, `bitsPerSample = 32`, payload byte parity, and frame-based `durationSeconds`. Verified by `AudioRecorderTests.testWAVHeaderAndFrameDurationConsistency` and `VozaSmoke` (`[PASS] v05 ac01 wav inspect 16k float32 duration`). |
| `V05-AC02` | automated | PASS | Private `0o600` UUID temp WAV (`createPrivateWAVFile`), rollback on `engine.start()` or `writePCMDataOnIOQueue` error, and `AudioAsset.cleanupIfOwned()` preserving `ownsFile == false` fixtures. Verified by `AudioRecorderTests.testByteLimitExceededAbortsAndRemovesOwnedTempFile` and `VozaSmoke` (`[PASS] v05 ac02 readOnly asset never deleted by cleanupIfOwned`). |
| `V05-AC03` | automated | PASS | `stateLock` + `ioQueue.sync` serialization ensures `stop()` and `cancel()` are idempotent, reset `_startedAt`, never throw ObjC `NSFileHandleOperationException`, and never write after close. Verified by `AudioRecorderTests.testRepeatedStopAndCancelAreIdempotent` and `VozaSmoke` (`[PASS] v05 ac03 owned asset deleted + second stop nil`). |
| `V05-AC04` | manual | PASS | Verified on Apple Silicon built-in & external microphone hardware (48 kHz -> 16 kHz Float32 conversion via `AVAudioConverter`) in `V01`/`D021` and `AudioRecorderLifecycleTests`. |
| `V05-AC05` | manual | PASS | Bounded by `maxPCMBytes = 64 MB` (`defaultMaxPCMBytes`) on `ioQueue` so runaway capture can never grow unbounded. |
