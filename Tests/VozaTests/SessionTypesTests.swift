import Foundation
import XCTest
@testable import VozaKit

final class SessionTypesTests: XCTestCase {
    // V06-AC01: SessionMode and SessionSettingsSnapshot roundtrip through JSON with UI-independent rawValues.
    func testSessionTypesCodableRoundTripAndStableRawValues() throws {
        XCTAssertEqual(SessionMode.literal.rawValue, "literal")
        XCTAssertEqual(SessionMode.polished.rawValue, "polished")

        let snap = SessionSettingsSnapshot(
            language: "es",
            preferredModelId: "large-v3-turbo",
            requestedMode: .polished,
            autoLearn: true,
            playSound: false,
            whisperBinary: "/custom/whisper-cli",
            hasCleanupProvider: true
        )
        let encoded = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SessionSettingsSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snap)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    // V06-AC02: ProcessingOutcome distinguishes unchanged, rewritten, unavailable, rejected, and cancelled.
    func testProcessingOutcomeStates() async {
        let lit = ProcessingOutcome.literalUnchanged("hola")
        XCTAssertEqual(lit.status, .unchanged)
        XCTAssertFalse(lit.didRewrite)
        XCTAssertEqual(lit.appliedMode, .literal)

        let samePolished = ProcessingOutcome.polishedSuccess(original: "Hola.", result: "Hola.")
        XCTAssertEqual(samePolished.status, .unchanged)
        XCTAssertFalse(samePolished.didRewrite)
        XCTAssertEqual(samePolished.appliedMode, .polished)

        let rewritten = ProcessingOutcome.polishedSuccess(original: "hola", result: "Hola.")
        XCTAssertEqual(rewritten.status, .rewritten)
        XCTAssertTrue(rewritten.didRewrite)

        let unavail = ProcessingOutcome.polishedFallback(rawText: "hola", status: .unavailable, reason: "timeout")
        XCTAssertEqual(unavail.status, .unavailable)
        XCTAssertEqual(unavail.appliedMode, .literal)
        XCTAssertFalse(unavail.didRewrite)

        let rejected = ProcessingOutcome.polishedFallback(rawText: "hola", status: .rejected, reason: "empty")
        XCTAssertEqual(rejected.status, .rejected)

        let cancelled = ProcessingOutcome.cancelled(rawText: "hola", requestedMode: .polished)
        XCTAssertEqual(cancelled.status, .cancelled)
    }

    // V06-AC03 & V07-AC04: Snapshot captured from Config does not mutate when Config is modified later.
    func testSnapshotRemainsImmutableAfterConfigChanges() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let cfg = Config(paths: env.paths)
        cfg.setLanguage("es")
        cfg.setModel("small-q5_1")
        cfg.setAutoLearn(true)

        let snapshot = SessionSettingsSnapshot(from: cfg)
        XCTAssertEqual(snapshot.language, "es")
        XCTAssertEqual(snapshot.preferredModelId, "small-q5_1")
        XCTAssertTrue(snapshot.autoLearn)

        // Mutate Config after snapshot creation
        cfg.setLanguage("en")
        cfg.setModel("base.en")
        cfg.setAutoLearn(false)

        XCTAssertEqual(snapshot.language, "es", "In-flight snapshot must not change when Config mutates")
        XCTAssertEqual(snapshot.preferredModelId, "small-q5_1")
        XCTAssertTrue(snapshot.autoLearn)
    }
}
