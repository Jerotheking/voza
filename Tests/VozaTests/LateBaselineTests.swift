import XCTest
@testable import VozaKit

/// D034 late-baseline mode (the Sintelia case): apps that expose no AX text
/// at paste time (Electron/Chromium) get their AX tree forced on and are
/// watched with a LIVE baseline captured after the paste. D040: the wake is
/// attribute-only (`AXManualAccessibility` on AXWebAreas) — VoiceOver was
/// deleted from the codebase and can never be launched again. All tests
/// inject a fake reader/clock/sink/wake — zero real AX, zero real sleeps.
final class LateBaselineTests: XCTestCase {
    override class func setUp() { LearningLog.isMutedForTests = true }
    private func makeSession(pasted: String) -> Paster.Session {
        Paster.Session(element: nil, pastedText: pasted,
                       selectedRange: NSRange(location: 0, length: 0),
                       fieldBefore: "", startedAt: Date())
    }

    /// Scripted reader: drives its own clock forward per poll, like the real
    /// loop does (poll → read → maybe stabilize).
    private final class Script {
        private(set) var now = Date(timeIntervalSince1970: 1_700_000_000)
        private var values: [String?]
        private(set) var polls = 0
        var advancePerPoll: TimeInterval = 0.8
        init(values: [String?]) { self.values = values }
        func read() -> String? {
            defer { polls += 1 }
            let v = values[min(polls, values.count - 1)]
            now = now.addingTimeInterval(advancePerPoll)
            return v
        }
        var clock: Clock { ScriptClock(self) }
    }

    /// Test-only Clock bound to the script's mutable time (@unchecked Sendable
    /// is safe here: single-threaded test execution by construction).
    private final class ScriptClock: Clock, @unchecked Sendable {
        private let script: LateBaselineTests.Script
        init(_ s: LateBaselineTests.Script) { script = s }
        var now: Date { script.now }
        var uptimeSeconds: Double { script.now.timeIntervalSince1970 }
    }

    func testLearnsWhenTreeAppearsLate() {
        // Poll 1-2: AX tree still building (nil). Poll 3: field appears WITH
        // our paste (baseline captured). Poll 4-5: user's typed correction
        // stabilizes. → lesson recorded.
        let script = Script(values: [nil, nil, "Sintelia.", "Sinteliä.", "Sinteliä."])
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watchLateBaseline(
            session: makeSession(pasted: "Sintelia."),
            clock: script.clock,
            readFocused: { script.read() },
            sleep: { _ in },
            sink: sink,
            config: .init(pollIntervalSeconds: 0.01, windowSeconds: 20, stabilitySamples: 2),
            force: { false }
        )

        XCTAssertTrue(learned)
        XCTAssertEqual(sink.pairs.count, 1)
        // extractPair trims trailing punctuation to word boundaries — the
        // stored lesson is the word pair itself.
        XCTAssertEqual(sink.pairs.first?.heard, "Sintelia")
        XCTAssertEqual(sink.pairs.first?.said, "Sinteliä")
    }

    func testGivesUpWhenTreeNeverAppears() {
        let script = Script(values: [nil])
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watchLateBaseline(
            session: makeSession(pasted: "Sintelia."),
            clock: script.clock,
            readFocused: { script.read() },
            sleep: { _ in },
            sink: sink,
            // axWakeSeconds = 5.0 / poll 0.5 → 10 wake polls max, then window
            config: .init(pollIntervalSeconds: 0.5, windowSeconds: 0.1, stabilitySamples: 2),
            force: { false }
        )

        XCTAssertFalse(learned)
        XCTAssertTrue(sink.pairs.isEmpty)
    }

    func testContainmentDoesNotCountAsEdit() {
        // The field exposes MORE text than our paste (chat history) with our
        // paste inside: that must count as "unchanged", not as an edit.
        let script = Script(values: ["hola\nSintelia.\nchao", "hola\nSintelia.\nchao"])
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watchLateBaseline(
            session: makeSession(pasted: "Sintelia."),
            clock: script.clock,
            readFocused: { script.read() },
            sleep: { _ in },
            sink: sink,
            config: .init(pollIntervalSeconds: 0.01, windowSeconds: 0.05, stabilitySamples: 2),
            force: { false }
        )

        XCTAssertFalse(learned, "containment alone must never produce a lesson")
        XCTAssertTrue(sink.pairs.isEmpty)
    }

    // MARK: D040 — attribute-only forcing, no VoiceOver anywhere

    func testForcesEveryPollViaWakeSeam() {
        // The wake seam runs on EVERY poll of the wake window (Chromium builds
        // its web tree lazily; a single early set often doesn't stick), and a
        // true wake is not itself "the tree is up" — only a readable field is.
        let script = Script(values: [nil, nil, "Sintelia.", "Sinteliä.", "Sinteliä."])
        var wakeCalls = 0
        let sink = CorrectionWatcher.QASink()

        let learned = CorrectionWatcher.watchLateBaseline(
            session: makeSession(pasted: "Sintelia."),
            clock: script.clock,
            readFocused: { script.read() },
            sleep: { _ in },
            sink: sink,
            config: .init(pollIntervalSeconds: 0.5, windowSeconds: 20, stabilitySamples: 2),
            force: { wakeCalls += 1; return true }
        )

        XCTAssertTrue(learned)
        XCTAssertEqual(wakeCalls, 3, "wake fires every poll until the baseline appears")
    }
}

/// LearningLog format/rotation — hermetic via the sink seam.
final class LearningLogTests: XCTestCase {
    override class func setUp() { LearningLog.isMutedForTests = false }
    func testEventLines() {
        let log = LearningLog()
        var lines: [String] = []
        log.sink = { lines.append($0) }

        log.event(.start(hasElement: false))
        log.event(.learned(heard: "prueva", said: "prueba"))
        log.event(.expired)


        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("| start | ax=late-baseline"), lines[0])
        XCTAssertTrue(lines[1].contains("| learned | prueva -> prueba"), lines[1])
        XCTAssertTrue(lines[2].contains("| expired |"), lines[2])
        // Timestamp prefix present (POSIX HH:mm:ss → first char is a digit).
        XCTAssertTrue(lines[0].first?.isNumber == true, lines[0])
    }

    func testLongPairsTruncatedInLog() {
        let log = LearningLog()
        var lines: [String] = []
        log.sink = { lines.append($0) }

        let long = String(repeating: "a", count: 100)
        log.event(.learned(heard: long, said: long))

        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThanOrEqual(lines[0].count, 150, "long pairs must be truncated")
    }

    func testNoVoiceOverRemainsInLogFormat() {
        // D040 contract pin: the VoiceOver event is deleted from the log
        // vocabulary. The old "wake | voiceover…" line must be impossible to
        // emit again — nothing can re-introduce a speaking/blipping path.
        // (Runs in this class because LateBaselineTests mutes globally.)
        let log = LearningLog()
        var lines: [String] = []
        log.sink = { lines.append($0) }

        log.event(.start(hasElement: false))
        log.event(.learned(heard: "a", said: "b"))
        log.event(.expired)
        log.event(.axNeverWoke(accepted: 0, unsupported: 7))

        XCTAssertEqual(lines.count, 4)
        XCTAssertFalse(lines.contains { $0.lowercased().contains("voiceover") || $0.contains("wake |") },
                       "no VoiceOver line may ever be logged again")
        XCTAssertTrue(lines[3].contains("ax-never-woke"), lines[3])
    }
}
