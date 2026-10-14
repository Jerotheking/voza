import Darwin
import Foundation
import XCTest
@testable import VozaKit

final class ProcessRunnerTests: XCTestCase {
    func testLargeStdoutAndStderrDrainWithoutDeadlock() throws {
        let runner = ProcessRunner(maxStdoutBytes: 2 * 1024 * 1024, maxStderrBytes: 2 * 1024 * 1024)
        let script = "import sys; sys.stdout.write('A' * 1048576); sys.stderr.write('B' * 262144)"
        let out = try runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", script],
            timeout: 10
        )
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertEqual(out.stdout.count, 1_048_576)
        XCTAssertEqual(out.stderr.count, 262_144)
    }

    func testProcessIgnoringSigtermIsEscalatedToSigkillAndReaped() throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-pr-sigterm-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let script = """
import os, signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(\"\(pidFile.path)\", 'w') as f:
    f.write(str(os.getpid()))
    f.flush()
while True:
    time.sleep(0.1)
"""
        let runner = ProcessRunner(sigkillGraceSeconds: 0.15)
        XCTAssertThrowsError(try runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", script],
            timeout: 0.35
        )) { error in
            XCTAssertEqual(error as? ProcessRunnerError, .timedOut(0.35))
        }

        if let pidStr = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let childPid = Int32(pidStr) {
            let alive = (Darwin.kill(childPid, 0) == 0)
            XCTAssertFalse(alive, "Child ignoring SIGTERM must not survive timeout")
        }
    }

    func testCancellationTerminatesAndThrowsCancelled() {
        let token = ProcessCancellationToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            token.cancel()
        }
        let runner = ProcessRunner(sigkillGraceSeconds: 0.1)
        XCTAssertThrowsError(try runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "import time; time.sleep(10)"],
            timeout: 10,
            cancellationToken: token
        )) { error in
            XCTAssertEqual(error as? ProcessRunnerError, .cancelled)
        }
    }

    func testExcessiveOutputThrowsOutputLimitExceeded() {
        let runner = ProcessRunner(maxStdoutBytes: 4096)
        XCTAssertThrowsError(try runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "import sys; sys.stdout.write('X' * 32768)"],
            timeout: 5
        )) { error in
            XCTAssertEqual(error as? ProcessRunnerError, .outputLimitExceeded(stream: "stdout", limitBytes: 4096))
        }
    }

    func testInvalidUTF8ThrowsDistinctError() {
        let runner = ProcessRunner()
        XCTAssertThrowsError(try runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "import sys; sys.stdout.buffer.write(b'\\xff\\xfe\\xfd')"],
            timeout: 5
        )) { error in
            XCTAssertEqual(error as? ProcessRunnerError, .invalidUTF8(stream: "stdout"))
        }
    }
}
