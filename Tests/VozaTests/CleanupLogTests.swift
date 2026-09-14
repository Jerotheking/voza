import XCTest
@testable import VozaKit

/// D029 — the cleanup diagnostics log. Contract: one sortable line per event,
/// rotation at 1 MB, write failures swallowed, hermetic via injected directory.
final class CleanupLogTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-logtest-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func lines() -> [String] {
        let text = try? String(contentsOf: dir.appendingPathComponent("cleanup.log"), encoding: .utf8)
        return (text ?? "").split(separator: "\n").map(String.init)
    }

    func testTimestampIsISO8601UTC() {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        XCTAssertEqual(CleanupLog.timestamp(date), f.string(from: date))
        // UTC by contract: the string ends in Z.
        XCTAssertTrue(CleanupLog.timestamp(date).hasSuffix("Z"))
    }

    func testWriteProducesOneParseableLine() {
        CleanupLog.write("mlx", "ok", seconds: 2.134, detail: "chars=87", directory: dir)
        let ls = lines()
        XCTAssertEqual(ls.count, 1)
        let parts = ls[0].components(separatedBy: " | ")
        XCTAssertEqual(parts.count, 5, "ts | provider | event | seconds | detail")
        XCTAssertEqual(parts[1].trimmingCharacters(in: .whitespaces), "mlx")
        XCTAssertEqual(parts[2], "ok")
        XCTAssertEqual(parts[3], "2.13s")
    }

    func testOptionalFieldsOmitted() {
        CleanupLog.write("chain", "fallback", directory: dir)
        let parts = lines()[0].components(separatedBy: " | ")
        XCTAssertEqual(parts.count, 3, "no seconds, no detail → 3 columns")
    }

    func testRotationMovesOldLogAside() {
        // Seed a log above the ceiling.
        let big = dir.appendingPathComponent("cleanup.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(repeating: 0x61, count: CleanupLog.maxBytes + 1).write(to: big)
        CleanupLog.write("mlx", "ok", directory: dir)
        // Active log now holds only the new line; the old content moved aside.
        XCTAssertEqual(lines().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("cleanup.old").path))
    }

    func testConcurrentWritesAllLand() {
        let group = DispatchGroup()
        let q = DispatchQueue(label: "logtest", attributes: .concurrent)
        for i in 0..<50 {
            group.enter()
            q.async {
                CleanupLog.write("mlx", "ev\(i)", directory: self.dir)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(lines().count, 50, "lock must serialize: no line lost")
    }
}
