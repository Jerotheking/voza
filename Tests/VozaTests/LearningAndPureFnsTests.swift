import XCTest
@testable import VozaKit

/// Hardening R3+R5 (docs/plan-glm/evidence/coverage-gap-report.md).
///
/// R3: the rewrite engine that touches every future dictation — the smoke
/// covers record/persist/prompt-budget, but `apply`/`diffCorrection` had only
/// happy-path examples. R5: small pure functions each guarding a bug class
/// already lived (malformed WAV, hallucinated non-speech markers, broken
/// medians, wrong disk budgets). All hermetic: pure statics, no disk.
final class LearningAndPureFnsTests: XCTestCase {

    private func correction(_ heard: String, _ said: String) -> Correction {
        Correction(id: UUID(), heard: heard, said: said, createdAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - R3: CorrectionStore.apply (rewrite engine)

    func testApplySingleWordFix() {
        let out = CorrectionStore.apply("esto es una prueva",
                                        corrections: [correction("prueva", "prueba")])
        XCTAssertEqual(out, "esto es una prueba")
    }

    /// The replacement mirrors the heard occurrence's case shape (ALL CAPS
    /// stays ALL CAPS, capitalized stays capitalized) — user-visible polish.
    func testApplyPreservesCaseShape() {
        let c = [correction("prueva", "prueba")]
        XCTAssertEqual(CorrectionStore.apply("ESTO ES UNA PRUEVA", corrections: c),
                       "ESTO ES UNA PRUEBA")
        XCTAssertEqual(CorrectionStore.apply("La Prueva nueva", corrections: c),
                       "La Prueba nueva")
        XCTAssertEqual(CorrectionStore.apply("la prueva", corrections: c),
                       "la prueba")
    }

    /// Every occurrence is replaced — repeated mistakes don't survive once.
    func testApplyReplacesAllOccurrences() {
        let out = CorrectionStore.apply("prueva y prueva",
                                        corrections: [correction("prueva", "prueba")])
        XCTAssertEqual(out, "prueba y prueba")
    }

    /// Several lessons apply simultaneously (each heard once per store; the
    /// regex alternation must not eat each other's matches).
    func testApplyMultipleCorrectionsTogether() {
        let out = CorrectionStore.apply("tiago la prueva",
                                        corrections: [correction("tiago", "Tiago"),
                                                      correction("prueva", "prueba")])
        XCTAssertEqual(out, "Tiago la prueba")
    }

    /// A replacement must never be re-processed by the same pass: if `said`
    /// contains `heard`, the output contains `said` verbatim, not an
    /// infinitely-corrected loop.
    func testApplyDoesNotReapplyInsideItsOwnReplacement() {
        let out = CorrectionStore.apply("dijo prueva",
                                        corrections: [correction("prueva", "la prueva")])
        XCTAssertEqual(out, "dijo la prueva")
        XCTAssertFalse(out.contains("la prueba"))
    }

    /// Word boundaries: a lesson for "casa" must never mutate "casación".
    func testApplyRespectsWordBoundaries() {
        let out = CorrectionStore.apply("la casación fue revisada",
                                        corrections: [correction("casa", "hogar")])
        XCTAssertEqual(out, "la casación fue revisada")
    }

    func testApplyEmptyCorrectionsOrNoMatchReturnsInput() {
        XCTAssertEqual(CorrectionStore.apply("texto", corrections: []), "texto")
        XCTAssertEqual(CorrectionStore.apply("texto limpio",
                                             corrections: [correction("prueva", "prueba")]),
                       "texto limpio")
    }

    // MARK: - R3: diffCorrection (what a lesson teaches)

    func testDiffCorrectionWordSwap() {
        let pair = CorrectionStore.diffCorrection(original: "esto es una prueva",
                                                  corrected: "esto es una prueba")
        XCTAssertEqual(pair?.heard, "prueva")
        XCTAssertEqual(pair?.said, "prueba")
    }

    /// Case-only fix still teaches (char-level fallback): "tiago" → "Tiago".
    func testDiffCorrectionCaseOnlyFix() {
        let pair = CorrectionStore.diffCorrection(original: "hola tiago",
                                                  corrected: "hola Tiago")
        XCTAssertEqual(pair?.heard, "tiago")
        XCTAssertEqual(pair?.said, "Tiago")
    }

    /// A pure insertion (or deletion) has no replacement pair — the watcher
    /// must not invent a lesson from the user typing extra words.
    func testDiffCorrectionRefusesPureInsertionOrDeletion() {
        XCTAssertNil(CorrectionStore.diffCorrection(original: "hola",
                                                    corrected: "hola mundo"))
        XCTAssertNil(CorrectionStore.diffCorrection(original: "hola mundo",
                                                    corrected: "hola"))
    }

    func testDiffCorrectionRefusesNothingToLearn() {
        XCTAssertNil(CorrectionStore.diffCorrection(original: "igual",
                                                    corrected: "igual"))
        XCTAssertNil(CorrectionStore.diffCorrection(original: "  ", corrected: "x"))
        XCTAssertNil(CorrectionStore.diffCorrection(original: "x", corrected: ""))
    }

    // MARK: - R5: wavHeader (malformed-WAV bug class, CODE-MAP F06)

    /// Byte-exact RIFF/WAVE for Float32 mono: the header whisper.cpp consumed
    /// wrong when it was malformed ("caught during smoke" comment in source).
    func testWavHeaderByteLayout() {
        let h = AudioRecorder.wavHeader(dataBytes: 8_000) // 0.5 s @16 kHz
        XCTAssertEqual(h.count, 44)
        XCTAssertEqual(String(data: h[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(h.subdata(in: 4..<8), withLE(UInt32(36 + 8_000)))
        XCTAssertEqual(String(data: h[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: h[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(h.subdata(in: 16..<20), withLE(UInt32(16)))
        XCTAssertEqual(h.subdata(in: 20..<22), withLE(UInt16(3)))   // IEEE float
        XCTAssertEqual(h.subdata(in: 22..<24), withLE(UInt16(1)))   // mono
        XCTAssertEqual(h.subdata(in: 24..<28), withLE(UInt32(16_000)))
        XCTAssertEqual(h.subdata(in: 28..<32), withLE(UInt32(64_000))) // 16k×1ch×4B
        XCTAssertEqual(h.subdata(in: 32..<34), withLE(UInt16(4)))
        XCTAssertEqual(h.subdata(in: 34..<36), withLE(UInt16(32)))
        XCTAssertEqual(String(data: h[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(h.subdata(in: 40..<44), withLE(UInt32(8_000)))
    }

    /// Byte rate tracks a custom sample rate (rate × 1 ch × 4 B/sample).
    func testWavHeaderCustomSampleRate() {
        let h = AudioRecorder.wavHeader(dataBytes: 4, sampleRate: 44_100)
        XCTAssertEqual(h.subdata(in: 24..<28), withLE(UInt32(44_100)))
        XCTAssertEqual(h.subdata(in: 28..<32), withLE(UInt32(176_400)))
    }

    private func withLE(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }
    private func withLE(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    // MARK: - R5: isNonSpeechMarker (hallucinated-marker bug class)

    /// "a 0.6 s silent recording transcribed as [BLANK_AUDIO]" must paste
    /// nothing, not a hallucinated marker (source comment, Transcriber).
    func testIsNonSpeechMarkerDetection() {
        XCTAssertTrue(Transcriber.isNonSpeechMarker("[BLANK_AUDIO]"))
        XCTAssertTrue(Transcriber.isNonSpeechMarker("(wind blowing)"))
        XCTAssertTrue(Transcriber.isNonSpeechMarker("  [Música]  "))
        XCTAssertFalse(Transcriber.isNonSpeechMarker("hola mundo"))
        XCTAssertFalse(Transcriber.isNonSpeechMarker("[BLANK_AUDIO] hola")) // marker + real text
        // Real dictation is never marker-shaped-and-tiny; long bracketed text
        // is content, not a marker (length guard).
        XCTAssertFalse(Transcriber.isNonSpeechMarker("[\(String(repeating: "a", count: 60))]"))
    }

    // MARK: - R5: medianRTF (performance suggestions integrity)

    func testMedianRTFOddEvenAndInsufficientSamples() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let monitor = PerformanceMonitor(paths: env.paths, clock: env.clock, defaults: env.defaults)

        monitor._test_setSamples([0.5, 0.2, 0.9], model: "small.en")
        XCTAssertEqual(try XCTUnwrap(monitor.medianRTF(model: "small.en")), 0.5, accuracy: 0.0001)

        monitor._test_setSamples([0.4, 0.1, 0.9, 0.2], model: "tiny.en") // even: (0.2+0.4)/2
        XCTAssertEqual(try XCTUnwrap(monitor.medianRTF(model: "tiny.en")), 0.3, accuracy: 0.0001)

        monitor._test_setSamples([0.4, 0.1], model: "short")             // < 3 samples
        XCTAssertNil(monitor.medianRTF(model: "short"))
        XCTAssertNil(monitor.medianRTF(model: "never-seen"))
    }

    // MARK: - R5: requiredFreeMB (disk budget per model, audit v2 §3.10)

    /// Size plus a 256 MB working margin, floored to whole MiB — a wrong
    /// budget either blocks valid downloads or accepts doomed ones.
    func testRequiredFreeMBIsSizePlusMargin() {
        let model = WhisperModel(id: "test", file: "test.bin",
                                 bytes: 1_500_000_000, sha256: "a")
        // (1_500_000_000 + 256_000_000) / 1_048_576 = 1674.6 → Int truncates to 1674.
        XCTAssertEqual(ReadinessChecker.requiredFreeMB(for: model), 1_674)
        // Sanity: never below the raw model size.
        XCTAssertGreaterThanOrEqual(ReadinessChecker.requiredFreeMB(for: model),
                                    model.bytes / 1_048_576)
    }
}
