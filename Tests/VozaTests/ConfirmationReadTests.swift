import XCTest
@testable import VozaKit

/// D036 — the stability gate fired mid-composition: the user paused inside
/// the macOS accent menu (composing "sinteliä") and the watcher learned the
/// frozen fragment ("sinteli" ← "sin teia"). Fix under test: after the
/// stability gate, one extra read after a confirmation pause must observe
/// resumed typing (field changed again → no lesson, session re-arms), reader
/// hiccups (nil → re-arm), and only a still-identical field may learn.
/// All tests run the REAL watch() loop at the injection seam — no AX, no
/// real sleeps, no real store.
final class ConfirmationReadTests: XCTestCase {
    override class func setUp() { LearningLog.isMutedForTests = true }

    private func makeSession(pasted: String, fieldBefore: String) -> Paster.Session {
        Paster.Session(element: AXUIElementCreateSystemWide(), pastedText: pasted,
                       // paste lands at the END of the pre-existing context,
                       // otherwise expectedField puts our text BEFORE it
                       selectedRange: NSRange(location: (fieldBefore as NSString).length, length: 0),
                       fieldBefore: fieldBefore, startedAt: Date())
    }

    /// Time-driven scripted reader like LateBaselineTests.Script: each poll
    /// consumes the value current for that time window. Index -1 = nil
    /// (unreadable hiccup).
    private final class Timeline {
        private(set) var now = Date(timeIntervalSince1970: 1_700_000_000)
        private let windows: [(until: TimeInterval, value: String?)]
        init(windows: [(TimeInterval, String?)]) { self.windows = windows }
        func read() -> String? {
            let t = now.timeIntervalSince1970 - 1_700_000_000
            for (until, value) in windows where t < until { return value }
            return windows.last?.value
        }
        var clock: Clock { TimelineClock(self) }
        func advance(_ d: TimeInterval) { now = now.addingTimeInterval(d) }
    }
    private final class TimelineClock: Clock, @unchecked Sendable {
        private let tl: Timeline
        init(_ tl: Timeline) { self.tl = tl }
        var now: Date { tl.now }
        var uptimeSeconds: Double { tl.now.timeIntervalSince1970 }
    }

    private let cfg = CorrectionWatcher.WatchConfig(
        pollIntervalSeconds: 0.8, windowSeconds: 20, stabilitySamples: 2)

    func testAccentMenuResumedTypingDoesNotLearnPrematurely() {
        // Real "sinteliä" case, replayed on the timeline: paste in field, user
        // edits (t=1.6–3.2 s), freezes in the accent menu 1.6 s (the old bug:
        // learned HERE), then RESUMES typing (t=4.8+). The confirm read must
        // see the resumed value and refuse; the session re-arms and keeps
        // watching until the real correction settles.
        let expected = "Hola, esto es una sin teia"
        let frozen = "Hola, esto es una sinteli"
        let resumed = "Hola, esto es una sinteliä." // still moving...
        let settled = "Hola, esto es una Sinteliä." // final correction
        let tl = Timeline(windows: [
            (0.8, expected),
            (1.6, expected),
            (2.4, frozen),
            (3.2, frozen),          // stable ×2 → gate fires → confirm read
            (4.0, resumed),         // confirm sees RESUMED typing → no lesson
            (4.8, resumed),
            (5.6, settled),
            (6.4, settled),         // stable ×2 → gate → confirm → STILL settled
            (.infinity, settled),
        ])
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watch(
            session: makeSession(pasted: "sin teia", fieldBefore: "Hola, esto es una "),
            clock: tl.clock,
            readField: { _ in tl.read() },
            sleep: { tl.advance($0) },
            sink: sink,
            config: cfg)

        XCTAssertTrue(learned, "the settled correction must be learned eventually")
        XCTAssertEqual(sink.pairs.count, 1)
        XCTAssertEqual(sink.pairs.first?.heard, "sin teia")
        XCTAssertEqual(sink.pairs.first?.said, "Sinteliä")
    }

    func testReaderHiccupDuringConfirmationReArms() {
        // Stable ×2 → confirm read hits an AX hiccup (nil) → session re-arms
        // instead of dying; the real correction that follows still learns.
        let expected = "hola prueva"
        let fixed = "hola prueba"
        let tl = Timeline(windows: [
            (0.8, expected),
            (1.6, expected),
            (2.4, fixed),
            (3.2, fixed),           // gate → confirm read → nil (hiccup)
            (4.0, nil),
            (4.8, fixed),
            (5.6, fixed),           // stable ×2 again → confirm reads fixed
            (.infinity, fixed),
        ])
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watch(
            session: makeSession(pasted: "prueva", fieldBefore: "hola "),
            clock: tl.clock,
            readField: { _ in tl.read() },
            sleep: { tl.advance($0) },
            sink: sink,
            config: cfg)

        XCTAssertTrue(learned, "a reader hiccup must not kill the session")
        XCTAssertEqual(sink.pairs.first?.heard, "prueva")
        XCTAssertEqual(sink.pairs.first?.said, "prueba")
    }
}
