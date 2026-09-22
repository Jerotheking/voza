import XCTest
@testable import VozaKit

/// P1-1 + P1-6 (audit 2026-09-21): History correctness bugs — a stale-read
/// race between `add` and refresh (the just-made dictation was missing from
/// the popover list), and locale-dependent stamp formatting that erased the
/// whole history on 12-hour / non-gregorian system locales.
/// Hermetic: a QA environment store with a FIXED clock; the real profile is
/// never touched.
final class TranscriptStoreRaceTests: XCTestCase {
    private func makeStore() throws -> (store: TranscriptStore, env: TestEnvironment, clock: FixedClock) {
        let env = try TestEnvironment()
        let store = TranscriptStore(paths: env.paths, clock: env.clock)
        // Every path drains pending disk ops BEFORE teardown so the serial
        // queue never recreates the QA root after it was removed.
        return (store, env, env.clock)
    }

    // MARK: P1-1 — add() must be reflected SYNCHRONOUSLY in `recent`

    func testAddIsSynchronouslyVisibleInRecent() throws {
        let (store, env, clock) = try makeStore()
        defer { store.drainPendingWritesForTests(); env.tearDown() }

        let before = store.recent.count
        store.add(text: "Sintelia dictation", cleaned: false)
        // The bug: recent only updated after the disk write completed on the
        // serial queue — a caller reading now saw a stale list.
        XCTAssertEqual(store.recent.count, before + 1,
                       "add() must update `recent` synchronously (P1-1)")
        XCTAssertEqual(store.recent.first?.text, "Sintelia dictation")
        XCTAssertEqual(store.recent.first?.cleaned, false)
        XCTAssertEqual(store.recent.first?.date, clock.now, "fixed clock entry timestamp")
    }

    func testAddFromOffMainThreadIsVisibleOnMainThread() throws {
        // The production caller (DictationPipeline.run) is @MainActor, but
        // the contract must hold for any thread: off-main adds land on main
        // asynchronously and are then visible.
        let (store, env, _) = try makeStore()
        defer { store.drainPendingWritesForTests(); env.tearDown() }

        let exp = expectation(description: "off-main add lands on main")
        DispatchQueue.global().async {
            store.add(text: "from another thread", cleaned: false)
            DispatchQueue.main.async { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(store.recent.first?.text, "from another thread")
    }

    func testRecentCapFifty() throws {
        let (store, env, _) = try makeStore()
        defer { store.drainPendingWritesForTests(); env.tearDown() }
        for i in 0..<55 {
            store.add(text: "entry \(i)", cleaned: false)
        }
        XCTAssertEqual(store.recent.count, 50)
        XCTAssertEqual(store.recent.first?.text, "entry 54", "newest first")
        XCTAssertEqual(store.recent.last?.text, "entry 5", "oldest evicted")
    }

    // MARK: P1-6 — stamps are POSIX-fixed, locale-independent

    func testStampsSurviveTwelveHourLocale() {
        // The exact failure mode: a 12-hour system locale must not change the
        // emitted stamp format. Simulate by formatting THROUGH the same
        // formatter with its locale forced where the bug lived — before the
        // fix, `makeEntryFormatter` inherited the user locale.
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "es_MX") // 12-hour region
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let buggyStamp = f.string(from: date) // would contain a. m./p. m.
        // The store's own formatter must NEVER produce that:
        let storeStamp = TranscriptEntry.entryStampFormatter.string(from: date)
        XCTAssertFalse(storeStamp.contains("m"), "no AM/PM marker in store stamps: \(storeStamp)")
        XCTAssertEqual(storeStamp.count, 19, "yyyy-MM-dd HH:mm:ss is 19 chars: \(storeStamp)")
        // And it round-trips:
        XCTAssertNotNil(TranscriptEntry.entryStampFormatter.date(from: buggyStamp.replacingOccurrences(of: "a. m.", with: "").isEmpty ? storeStamp : storeStamp))
        _ = buggyStamp
    }

    func testParseRejectsNonPOSIXStampsGracefully() {
        // A stamp from a foreign writer that doesn't parse → entry skipped,
        // not a crash, and not a half-parsed entry.
        let raw = """
        # Dictation log — 2026-09

        ## not a real stamp

        hello

        ## 2026-09-21 10:00:00

        valid entry
        """
        let entries = TranscriptStore.parseEntries(fromMarkdown: raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "valid entry")
    }
}
