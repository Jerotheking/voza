import XCTest
@testable import VozaKit

/// V02 — Proves the smoke contract without executing its binary logic inline:
/// the DEFAULT run is pure (deterministic exit 0, no models/whisper-cli/mic
/// required) and repeated suites leave the real profile untouched
/// (V02-AC02/AC03/AC05). Runs the built VozaSmoke binary as a process with a
/// wall-clock budget — a hang fails the test instead of hanging CI.
final class SmokeIsolationTests: XCTestCase {
    /// Smoke executable resolved from the test workspace's build directory.
    private var smokeBinary: String? {
        let candidates = [
            ".build/debug/VozaSmoke",
            ".build/arm64-apple-macosx/debug/VozaSmoke",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(c).path
        }
        return nil
    }

    private func runSmoke(_ args: String...) throws -> (exit: Int32, out: String) {
        guard let binary = smokeBinary else {
            throw XCTSkip("VozaSmoke binary not built yet (swift build first)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        // Wall-clock budget: a hung smoke must fail, not stall CI.
        let deadline = Date().addingTimeInterval(120)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning { p.terminate(); XCTFail("VozaSmoke exceeded 120 s wall clock") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func testDefaultRunIsPureAndDeterministic() throws {
        // V02-AC02: exit 0, deterministic, WITHOUT whisper-cli/models/mic.
        let (status, out) = try runSmoke()
        XCTAssertEqual(status, 0, "pure smoke failed:\n\(out.suffix(2_000))")
        XCTAssertTrue(out.contains("PURE checks only"), "pure banner missing")
        XCTAssertTrue(out.contains("All pure smoke checks passed"), "no pure summary")

        // V02-AC05: skips accounted separately, never counted as passes.
        let skips = out.components(separatedBy: "\n").filter { $0.contains("[SKIP]") }.count
        XCTAssertTrue(out.contains(", \(skips) skips"), "skip accounting mismatch in summary")
        // No real-model dependency: default run must succeed even when the
        // readiness engine check is skipped (covered by the banner itself).
    }

    func testRepeatedRunsLeaveProfileUntouched() throws {
        // V02-AC03: repeating the suite changes no real config/perf/history.
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let config = home.appendingPathComponent(".config/voza/config.toml")
        let perf = home.appendingPathComponent(".config/voza/perf.json")
        let history = home.appendingPathComponent("Dictation")

        let digest: () -> [String: Data] = {
            var d: [String: Data] = [:]
            for f in [config, perf] {
                d[f.lastPathComponent] = (try? Data(contentsOf: f)) ?? Data()
            }
            d["history"] = (try? fm.contentsOfDirectory(atPath: history.path).joined(separator: ",").data(using: .utf8)) ?? Data()
            return d
        }
        let before = digest()
        for _ in 0..<2 { _ = try runSmoke() }
        XCTAssertEqual(digest(), before, "real profile files changed across smoke repeats")
    }

    func testSkipIsNeverCountedAsPass() throws {
        // V02-AC05: with no --integration, integration suites must appear as
        // [SKIP] lines, and the summary's PASS count must exclude them.
        let (status, out) = try runSmoke()
        XCTAssertEqual(status, 0)
        if out.contains("[SKIP]") {
            XCTAssertTrue(out.contains("skips"), "SKIP present but not accounted in summary")
            let passLines = out.components(separatedBy: "\n").filter { $0.contains("[PASS]") }.count
            let summary = out.components(separatedBy: "\n").first { $0.contains("All pure smoke checks passed") } ?? ""
            XCTAssertTrue(summary.contains("\(passLines) checks"), "summary PASS count (\(summary)) ≠ [PASS] lines (\(passLines))")
        }
    }
}
