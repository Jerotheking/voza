# Memory audit — "idle uses ~1 GB" investigation (2026-09-08)

Owner report: Voza idle ≈ 1 GB RAM. Method: measure first (Matt-Pocock-style
discipline — evidence before hypotheses), on macOS host, all numbers via
`top -l 1 -pid <PID>` (physical footprint), `leaks`, `vmmap --summary`.

## Measurements

| Variant | Idle RSS | Soak | Peak | leaks | CPU |
|---|---|---|---|---|---|
| build/Voza.app v0.3.0 (release, packaged) | 16–17 MB | flat over 2.5 min (6 samples × 15 s) | 17.1 MB | 284 objs / 14,272 B (Swift runtime noise) | 0.0% |
| .build/debug/Voza (debug binary) | 16 MB | 3 samples flat | — | — | 0.0% |
| Voza process during this audit | n/a | not running at audit start (user had quit it) | — | — | — |

`vmmap` (release, idle): Physical footprint 17.0 MB, peak 17.1 MB; largest
zone MALLOC_SMALL 37.5 MB virtual / 5.8 MB resident. No IOKit/graphics bloat.

Verdict: **the ~1 GB report did not reproduce in any runnable variant.**
Static audit of the idle path (VozaApp → AppState init → HotKeyManager event
tap → timer only while recording) found no allocation loop; the only recurring
work at idle is the menu-bar icon and the event tap.

## Most probable explanations for the 1 GB sighting (unverified — [ASSUMED])

1. **whisper-cli child during transcription**: the loaded GGML model
   (small-q5_1 ≈ 190 MB file, ~400–500 MB in RAM as compute graphs) is held by
   the whisper-cli process; Activity Monitor's memory column for the parent
   tree, or checking right after a dictation, reads as "Voza" memory.
2. **Activity Monitor "Memory" column** = physical footprint + compressed +
   swap, which inflates small apps several-fold vs RSS.
3. **A crash-loop of debug runs** earlier in development leaving several
   instances/children alive simultaneously.

## Hygiene fix applied (outside V01 file ownership — owner-directed task)

`AudioRecorder.stop()` now fully resets `outputURL`/`pcmBytes`/`startedAt`
after transferring file ownership. Previously the finished session's URL and
byte counter stayed set until the next start — negligible for RAM, but wrong
state hygiene and a trap for future lifecycle work (V05).

## Guards added

- v01 smoke remains green after the fix (14/14, exit 0) — log:
  evidence/V01/v01-hermetic-isolation/smoke-v01.log (re-run appended).
- Follow-up candidates (NOT implemented — V05 owns recorder lifecycle): exact
  44-byte file assertion after stop(); cancel-after-stop idempotency check.

## Known pre-existing build characteristic (registered, not a regression)

`swift build -c release --product VozaSmoke` fails: `@testable import VozaKit`
is unavailable in release SwiftPM configs. Full smoke suite has always been
debug-only. V02 (smoke/CI rework) should either drop @testable from VozaSmoke
or keep smoke debug-only explicitly in CI.
