import XCTest
@testable import VozaKit

/// V01 hermeticity proofs: components construct and read without touching
/// disk, writes stay inside the QA root, the simulated clock drives dates and
/// elapsed time with zero sleeps, and teardown deletes only what it owns.
///
/// NOTE (V02): this target cannot compile under CommandLineTools; these run
/// under Xcode/toolchain with XCTest. The smoke `v01` mode mirrors the same
/// assertions for CLT environments.
@MainActor
final class TestEnvironmentTests: XCTestCase {
    // MARK: - V01-AC01: construction/reads create nothing, writes stay in QA

    func testComponentConstructionAndReadsCreateNothing() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        _ = Config(paths: env.paths)
        _ = PerformanceMonitor(paths: env.paths, clock: env.clock, defaults: env.defaults)
        let store = TranscriptStore(paths: env.paths, clock: env.clock)
        _ = LicenseManager(paths: env.paths, clock: env.clock, defaults: env.defaults)

        // Pure getters must not create anything either.
        _ = store.logDirectory.path
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.root.path),
                       "component construction or reads created the QA root")
    }

    func testConfigWriteStaysInsideQARoot() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let config = Config(paths: env.paths)
        config.setPlaySound(true)

        let written = env.paths.configFile
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path),
                      "config.toml missing inside QA root")
        let text = try String(contentsOf: written, encoding: .utf8)
        XCTAssertTrue(text.contains("play_sound = true"))
        // History tree must be untouched by a config write.
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.paths.history.path))
    }

    func testHistoryWriteStaysInsideQARoot() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let store = TranscriptStore(paths: env.paths, clock: env.clock)
        let marker = "v01-marker-\(UUID().uuidString.prefix(6))"
        store.add(text: marker, cleaned: false)
        drainMainQueue(seconds: 0.5)

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let monthFile = env.paths.history.appendingPathComponent("\(f.string(from: env.clock.now)).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: monthFile.path),
                      "history month file missing inside QA root")
        let text = try String(contentsOf: monthFile, encoding: .utf8)
        XCTAssertTrue(text.contains(marker))
        // The config tree must be untouched by a history write.
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.paths.configFile.path))
    }

    // MARK: - V01-AC02: simulated clock determines dates and elapsed time

    func testLicenseTrialUsesInjectedClockWithoutSleeping() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let license = LicenseManager(paths: env.paths, clock: env.clock, defaults: env.defaults)
        license.refreshIfNeeded()
        XCTAssertEqual(license.state, .trial(daysLeft: 14))

        // 15 simulated days pass instantly — no Thread.sleep anywhere.
        env.clock.advance(seconds: 15 * 86_400)
        license.refreshIfNeeded()
        XCTAssertEqual(license.state, .trialOver)
        // D063 (P1-2): rolling wall clock backward by 30 days must NOT revive the trial.
        env.clock.advance(seconds: 1, wallSeconds: -30 * 86_400)
        license.refreshIfNeeded()
        XCTAssertEqual(license.state, .trialOver)
        // Trial start persisted in the ISOLATED defaults only.
        XCTAssertNotNil(env.defaults.object(forKey: "voza.trialStart"))
    }

    func testD063UnicodeWordBoundariesAndDedupeInCorrectionStore() {
        let older = Correction(id: UUID(), heard: "piña", said: "PiñaVieja", createdAt: Date(timeIntervalSince1970: 100))
        let newer = Correction(id: UUID(), heard: "piña", said: "PiñaColada", createdAt: Date(timeIntervalSince1970: 200))
        let out = CorrectionStore.apply("Quiero una piña fría", corrections: [older, newer])
        XCTAssertEqual(out, "Quiero una PiñaColada fría")
    }

    func testV09AndV10ClipboardOverlapAndHistoryPrivacy() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        // V09: overlapping paste reuses original clipboard only when changeCount still matches Voza write
        XCTAssertTrue(Paster.shouldReusePendingOriginalClipboard(pendingChangeCount: 42, currentChangeCount: 42))
        XCTAssertFalse(Paster.shouldReusePendingOriginalClipboard(pendingChangeCount: 42, currentChangeCount: 43))
        XCTAssertFalse(Paster.shouldReusePendingOriginalClipboard(pendingChangeCount: nil, currentChangeCount: 42))

        // V10: persistToDisk == false keeps entry in RAM (`recent`) without writing ~/Dictation on disk
        let store = TranscriptStore(paths: env.paths, clock: env.clock)
        store.add(text: "solo en memoria", cleaned: false, persistToDisk: false)
        store.drainPendingWritesForTests()
        XCTAssertEqual(store.recent.first?.text, "solo en memoria")
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.paths.history.path),
                       "persistToDisk=false must never create or write history files on disk")

        // Writing with persistToDisk == true and then calling clearAll() removes both RAM and .md files
        store.add(text: "en disco", cleaned: false, persistToDisk: true)
        store.drainPendingWritesForTests()
        store.clearAll()
        store.drainPendingWritesForTests()
        XCTAssertTrue(store.recent.isEmpty)
        let remaining = (try? FileManager.default.contentsOfDirectory(at: env.paths.history, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(remaining.filter { $0.pathExtension == "md" }.isEmpty)
    }

    func testFixedClockWallAndElapsedAreIndependent() {
        let clock = FixedClock(wall: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(clock.uptimeSeconds, 0)
        clock.advance(seconds: 10, wallSeconds: 400_000) // wall jump ≠ elapsed
        XCTAssertEqual(clock.uptimeSeconds, 10)
        XCTAssertEqual(clock.now.timeIntervalSince1970, 1_700_000_000 + 400_000)
    }

    // MARK: - V01-AC03: teardown deletes only what it owns

    func testTeardownRemovesRootAndSuiteButSparesSibling() throws {
        let siblingParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: siblingParent, withIntermediateDirectories: true)
        let sentinel = siblingParent.appendingPathComponent("sentinel-\(UUID().uuidString)")
        try "do-not-delete".write(to: sentinel, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sentinel) }

        let env = try TestEnvironment()
        env.defaults.set("x", forKey: "voza.isolation.probe")
        try FileManager.default.createDirectory(at: env.paths.appSupport, withIntermediateDirectories: true)

        env.tearDown()

        XCTAssertFalse(FileManager.default.fileExists(atPath: env.root.path),
                       "QA root survived teardown")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path),
                      "teardown deleted a file it does not own")
        // The defaults suite is gone: a fresh handle sees no keys.
        let resurrected = UserDefaults(suiteName: "voza.tests.\(UUID().uuidString)") // fresh name can't see old keys
        XCTAssertNil(resurrected?.object(forKey: "voza.isolation.probe") ?? nil)
    }

    // MARK: - Helpers

    private func drainMainQueue(seconds: TimeInterval) {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 2)
    }
}
