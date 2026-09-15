import XCTest
@testable import VozaKit

/// D033 round-trip over an isolated QA environment (V01 pattern): learn →
/// persist → reload → apply → condition. Proves the two consumers of the
/// learned dictionary behave on real stored data, and that the `record`
/// length cap guards both of them.
final class CorrectionRoundTripTests: XCTestCase {
    func testLearnPersistApplyAndPrompt() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        XCTAssertTrue(store.all().isEmpty, "reads must never create files (V01-AC01)")

        // Learn two lessons (as the watcher / ✏️ path would), advancing the
        // deterministic clock so prompt ordering (newest first) is defined.
        store.record(heard: "prueva", said: "prueba")
        env.clock.advance(seconds: 60)
        store.record(heard: "tiago rey", said: "Tiago Rey")

        // Fresh instance over the SAME paths: persistence holds across process
        // boundaries (the property the dictionary depends on).
        let reloaded = CorrectionStore(paths: env.paths, clock: env.clock)
        XCTAssertEqual(reloaded.all().count, 2)

        // Consumer 1: word-boundary replacement, case-preserving, longest-first.
        let out = CorrectionStore.apply("hola prueva soy TIAGO REY", corrections: reloaded.all())
        XCTAssertEqual(out, "hola prueba soy TIAGO REY", out)

        // Consumer 2: whisper prompt budget — only the `said` phrases, capped.
        let prompt = reloaded.initialPrompt()
        XCTAssertEqual(prompt, "Tiago Rey, prueba")

        // Deleting one lesson stops its application immediately (the other
        // lesson keeps working).
        let prueva = try XCTUnwrap(reloaded.all().first { $0.heard == "prueva" })
        reloaded.delete(id: prueva.id)
        let after = CorrectionStore.apply("hola prueva soy tiago rey", corrections: reloaded.all())
        XCTAssertEqual(after, "hola prueva soy Tiago Rey", after)
    }

    func testRecordCapsRejectOversizedLessons() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let store = CorrectionStore(paths: env.paths, clock: env.clock)

        // The exact poison found in the live store (D033): a 352-char "heard"
        // phrase — an LLM system prompt that leaked through the manual path.
        let poison = String(repeating: "A", count: CorrectionWatcher.maxLearnedChars + 1)
        XCTAssertNil(store.record(heard: poison, said: "ok"))
        XCTAssertNil(store.record(heard: "ok", said: poison))
        XCTAssertEqual(store.all().count, 0, "oversized lessons must never persist")

        // The boundary is inclusive: exactly the cap is accepted.
        let atCap = String(repeating: "b", count: CorrectionWatcher.maxLearnedChars)
        XCTAssertNotNil(store.record(heard: "x", said: atCap))
        XCTAssertEqual(store.all().count, 1)
    }

    func testRecordUpdatesExistingHeardPhrase() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        let first = store.record(heard: "prueva", said: "prueva") // hmm, same → nil
        XCTAssertNil(first, "record refuses heard == said")

        _ = store.record(heard: "prueva", said: "prueba")
        let updated = store.record(heard: "prueva", said: "prueba!")
        XCTAssertNotNil(updated)
        XCTAssertEqual(store.all().count, 1, "re-recording the same heard phrase updates, never duplicates")
        XCTAssertEqual(store.all().first?.said, "prueba!")
        // createdAt preserved → ordering stable across updates.
        XCTAssertEqual(store.all().first?.id, updated?.id)
    }
}
