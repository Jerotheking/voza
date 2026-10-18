import Foundation
import XCTest
@testable import VozaKit

final class AudioRecorderTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-audiorecorder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // V05-AC01: WAV header is 44 bytes, IEEE Float32 (code 3), mono 16 kHz/32-bit, and duration matches frames.
    func testWAVHeaderAndFrameDurationConsistency() throws {
        let dir = try makeTempDir()
        let rec = AudioRecorder()
        // 16,000 samples = 1.0 second at 16 kHz
        let samples = [Float](repeating: 0.25, count: 16_000)
        try rec.appendSamplesForTesting(samples, directory: dir)

        let url = try XCTUnwrap(rec.stop())
        let asset = try XCTUnwrap(rec.lastAsset)
        XCTAssertEqual(asset.url, url)
        XCTAssertEqual(asset.frameCount, 16_000)
        XCTAssertEqual(asset.pcmBytes, 64_000)
        XCTAssertEqual(asset.durationSeconds, 1.0, accuracy: 0.0001)
        XCTAssertTrue(asset.ownsFile)

        // Independent inspection via AudioAsset.inspectWAV
        let inspected = try AudioAsset.inspectWAV(at: url, ownsFile: false)
        XCTAssertEqual(inspected.frameCount, 16_000)
        XCTAssertEqual(inspected.sampleRate, 16_000)

        // Read-only asset cleanupIfOwned() must NOT delete the file
        inspected.cleanupIfOwned()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "readOnly asset must never be deleted")

        // Owned asset cleanupIfOwned() deletes the temp file
        asset.cleanupIfOwned()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // V05-AC02: Byte limit / write failure cleans up temp file and leaves no orphan resources.
    func testByteLimitExceededAbortsAndRemovesOwnedTempFile() throws {
        let dir = try makeTempDir()
        // Sibling sentinel file in the same directory must never be touched
        let sentinel = dir.appendingPathComponent("keep.wav")
        try Data("sentinel".utf8).write(to: sentinel)

        let rec = AudioRecorder(maxPCMBytes: 1024)
        let samples = [Float](repeating: 0.1, count: 512) // 2048 bytes > 1024 limit
        XCTAssertThrowsError(try rec.appendSamplesForTesting(samples, directory: dir)) { error in
            XCTAssertEqual(error as? AudioRecorderError, .byteLimitExceeded)
        }
        XCTAssertNil(rec.stop(), "Failed write session must return nil on stop and delete its temp file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path), "Sibling file must remain intact")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining, ["keep.wav"], "Temp WAV must be deleted on write failure")
    }

    // V05-AC03: Repeated stop/cancel calls do not duplicate finalize or write after close.
    func testRepeatedStopAndCancelAreIdempotent() throws {
        let dir = try makeTempDir()
        let rec = AudioRecorder()
        try rec.appendSamplesForTesting([Float](repeating: 0.5, count: 1600), directory: dir)

        let firstURL = try XCTUnwrap(rec.stop())
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertNil(rec.stop(), "Second stop() must return nil")
        rec.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path), "cancel() after stop() must not delete already-transferred file")

        // Start a second session and cancel it -> deletes only the second session's temp file
        try rec.appendSamplesForTesting([Float](repeating: 0.5, count: 800), directory: dir)
        rec.cancel()
        rec.cancel()
        XCTAssertNil(rec.stop())
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining, [firstURL.lastPathComponent])
    }

    // D070: Whisper Auto-Gain boosts quiet speech (0.02 -> ~0.24), leaves silence (< 0.005) untouched,
    // and leaves normal speech (>= 0.35) untouched.
    func testWhisperModeAutoGainNormalizesQuietSpeechAndSparesSilence() throws {
        XCTAssertEqual(AudioRecorder.whisperGainMultiplier(forPeak: 0.001), 1.0, "Silence must never be amplified")
        XCTAssertEqual(AudioRecorder.whisperGainMultiplier(forPeak: 0.50), 1.0, "Normal speech must not be amplified")
        let quietGain = AudioRecorder.whisperGainMultiplier(forPeak: 0.05)
        XCTAssertEqual(quietGain, 11.0, accuracy: 0.01)

        let dir = try makeTempDir()
        let rec = AudioRecorder()
        try rec.appendSamplesForTesting([Float](repeating: 0.05, count: 1600), directory: dir)
        let url = try XCTUnwrap(rec.stop())
        let raw = try Data(contentsOf: url)
        let payload = raw.dropFirst(44)
        let firstSample = payload.withUnsafeBytes { $0.load(as: Float.self) }
        XCTAssertEqual(firstSample, 0.55, accuracy: 0.01, "Whispered sample (0.05) should be normalized to target peak (0.55)")
        try? FileManager.default.removeItem(at: url)
    }
}
