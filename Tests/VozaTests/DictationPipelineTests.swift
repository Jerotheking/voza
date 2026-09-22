import XCTest
@testable import VozaKit

/// D042 — the dictation flow as ONE deep module, proven hermetically.
/// Every test injects fakes for ALL seams: no whisper, no real stores, no
/// AX, no PerformanceMonitor writes. The only real I/O is a temp WAV file
/// this test owns and deletes, which is exactly what the pipeline itself
/// must manage (the deletion invariants are the point of several tests).
///
/// Ordering invariants pinned here (DictationPipeline.run() doc):
///   resolve → transcribe → (RTF w/ model actually used) → delete audio →
///   apply corrections → paste → log → (conditional) learning.
@MainActor
final class DictationPipelineTests: XCTestCase {
    /// Serial event log shared by the fakes — proves ordering, not just calls.
    private final class Events {
        var list: [String] = []
        func add(_ e: String) { list.append(e) }
    }

    private final class Box<T> { var value: T? }

    private final class World {
        let wav: URL
        var events = Events()
        var usedModel: String?
        var pasted: [String] = []
        var logged: [String] = []
        var learned: [Paster.Session] = []
        var notices: [String] = []
        var rtfRecorded: [(rtf: Double, model: String)] = []
        var cleanedFlags: [Bool] = []
        var corrected: String?

        init(wav: URL) { self.wav = wav }

        @MainActor
        static func make(
            dir: URL, transcribeText: String? = "hola mundo",
            resolved: DictationPipeline.ResolvedModel? =
                (WhisperModel(id: "small.en", file: "ggml-small.en.bin", bytes: 1, sha256: "x"),
                 "/models/ggml-small.en.bin"),
            transcriptionThrows: Error? = nil,
            accessibility: Bool = true, pasteReturnsSession: Bool = true,
            learn: Bool = true,
            applyTransform: ((String) -> String)? = nil,
            recordedSeconds: Double = 4, clockStart: Date = Date(timeIntervalSince1970: 1_700_000_000)
        ) -> (pipeline: DictationPipeline, world: World) {
            let wav = dir.appendingPathComponent("take.wav")
            FileManager.default.createFile(atPath: wav.path, contents: Data("RIFF".utf8))
            let world = World(wav: wav)
            var p = DictationPipeline(
                wavURL: wav, recordedSeconds: recordedSeconds,
                language: "en", preferredModelId: "small.en", learnEnabled: learn
            )
            var t0 = clockStart
            p.clock = { t0 += 2; return t0 } // every call advances 2 s: start=+2, end=+4
            p.resolveModel = { _, _ in
                world.events.add("resolve")
                return resolved
            }
            p.transcribe = { url, _, _, _ in
                world.events.add("transcribe")
                // Ordering invariant: audio must still exist while transcribing.
                world.usedModel = FileManager.default.fileExists(atPath: url.path) ? "alive" : "gone"
                if let e = transcriptionThrows { throw e }
                return transcribeText ?? ""
            }
            p.initialPrompt = { world.events.add("prompt"); return "prompt-text" }
            p.applyCorrections = { text in
                world.events.add("apply")
                world.corrected = applyTransform?(text) ?? text
                return world.corrected!
            }
            p.recordPerformance = { rtf, model in
                world.events.add("rtf")
                world.rtfRecorded.append((rtf, model))
            }
            p.onNotice = { world.notices.append($0) }
            p.paste = { text in
                world.events.add("paste")
                world.pasted.append(text)
                guard pasteReturnsSession else { return nil }
                return Paster.Session(element: nil, pastedText: text,
                                      selectedRange: NSRange(location: 0, length: 0),
                                      fieldBefore: "", startedAt: Date())
            }
            p.logTranscript = { text, cleaned in
                world.events.add("log")
                world.logged.append(text)
                world.cleanedFlags.append(cleaned)
            }
            p.startLearning = { session in
                world.events.add("learn")
                world.learned.append(session)
            }
            p.accessibilityGranted = { world.events.add("ax"); return accessibility }
            return (p, world)
        }
    }

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-pipeline-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: Happy path & ordering

    func testHappyPathFullOrderAndAudioDeletion() async {
        let (p, w) = World.make(dir: try! makeDir())
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        // Exact ordering, including that RTF is recorded BEFORE the audio is
        // gone (timing happens around transcription) and learning is LAST.
        XCTAssertEqual(w.events.list,
                       ["resolve", "prompt", "transcribe", "rtf", "apply", "ax", "paste", "log", "learn"])
        XCTAssertEqual(w.usedModel, "alive")    // audio existed while whisper ran
        XCTAssertEqual(w.pasted, ["hola mundo"])
        XCTAssertEqual(w.logged, ["hola mundo"])
        XCTAssertEqual(w.learned.count, 1)
        XCTAssertEqual(w.learned.first?.pastedText, "hola mundo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.wav.path)) // deleted on success
    }

    func testCorrectionsAppliedBeforePasteAndLog() async {
        let (p, w) = World.make(dir: try! makeDir(),
                                applyTransform: { $0.replacingOccurrences(of: "hola", with: "HOLA") })
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(w.pasted, ["HOLA mundo"])
        XCTAssertEqual(w.logged, ["HOLA mundo"]) // the log holds what the user got
    }

    // MARK: Fallback model

    func testFallbackNoticesAndRTFAttributedToModelActuallyUsed() async {
        let tiny = DictationPipeline.ResolvedModel(
            WhisperModel(id: "tiny.en", file: "ggml-tiny.en.bin", bytes: 1, sha256: "x"),
            "/models/ggml-tiny.en.bin")
        let (p, w) = World.make(dir: try! makeDir(), resolved: tiny)
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(w.notices.count, 1)
        XCTAssertTrue(w.notices[0].contains("tiny.en"))
        XCTAssertEqual(w.rtfRecorded.first?.model, "tiny.en") // never the preferred id
    }

    func testNoFallbackNoticeWhenPreferredUsed() async {
        let (p, w) = World.make(dir: try! makeDir())
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertTrue(w.notices.isEmpty)
    }

    func testRTFUsesInjectedClockAndFloor() async {
        // clock advances 2 s per call → transcription measured as 2 s.
        // recordedSeconds 4 → rtf 0.5.
        let (p, w) = World.make(dir: try! makeDir(), recordedSeconds: 4)
        let outcome = await p.run()
        XCTAssertEqual(w.rtfRecorded.first?.rtf ?? -1, 0.5, accuracy: 0.0001)

        // Floor: recordedSeconds 0 must divide by 0.5, never 0.
        let (p2, w2) = World.make(dir: try! makeDir(), recordedSeconds: 0)
        _ = await p2.run()
        XCTAssertEqual(w2.rtfRecorded.first?.rtf ?? -1, 4.0, accuracy: 0.0001)
    }

    // MARK: Failure paths — audio deleted on EVERY path

    func testModelNotFoundDeletesAudioAndFails() async {
        let (p, w) = World.make(dir: try! makeDir(), resolved: nil)
        let outcome = await p.run()
        XCTAssertEqual(outcome, .failed(TranscriptionError.modelNotFound.localizedDescription))
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.wav.path))
        XCTAssertTrue(w.logged.isEmpty)
        XCTAssertTrue(w.pasted.isEmpty)
        XCTAssertEqual(w.events.list, ["resolve"]) // nothing else ever ran
    }

    func testTranscriptionFailureDeletesAudioAndFails() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let (p, w) = World.make(dir: try! makeDir(), transcriptionThrows: Boom())
        let outcome = await p.run()
        XCTAssertEqual(outcome, .failed("boom"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.wav.path))
        XCTAssertTrue(w.pasted.isEmpty)
        XCTAssertTrue(w.rtfRecorded.isEmpty) // failed runs never pollute perf stats
    }

    func testAccessibilityDeniedLogsButNeverPastesOrLearns() async {
        let (p, w) = World.make(dir: try! makeDir(), accessibility: false)
        let outcome = await p.run()
        XCTAssertEqual(outcome, .failed(TranscriptionError.accessibilityDeniedMessage))
        XCTAssertEqual(w.logged, ["hola mundo"]) // transcript preserved for history
        XCTAssertTrue(w.pasted.isEmpty)
        XCTAssertTrue(w.learned.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.wav.path))
    }

    // MARK: P0-1 (audit 2026-09-21) — cloud Pulido connected, provider-gated

    func testCleanupRunsOnlyWhenInjectedAndApplies() async {
        let (p, w) = World.make(dir: try! makeDir())
        var pipeline = p
        pipeline.clean = { text in
            w.events.add("clean")
            return Cleaner.CleaningOutcome(text: text.uppercased(), applied: true, provider: "openai")
        }
        let outcome = await pipeline.run()
        XCTAssertEqual(outcome, .pasted)
        // Order pin: cleanup happens AFTER learned corrections, BEFORE paste.
        XCTAssertEqual(w.events.list, ["resolve", "prompt", "transcribe", "rtf", "apply", "clean", "ax", "paste", "log", "learn"])
        XCTAssertEqual(w.pasted, ["HOLA MUNDO"])
        // The history row records what ACTUALLY happened.
        XCTAssertTrue(w.cleanedFlags.first ?? false)
    }

    func testNoProviderMeansNoNetworkEver() async {
        // Production default with no provider configured: clean == nil —
        // zero network reachability from the flow.
        let (pipeline, w) = World.make(dir: try! makeDir())
        var p = pipeline
        if Config.shared.hasCleanupProvider {
            p.clean = nil // owner's real machine has a key; tests must not
        }
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertFalse(w.events.list.contains("clean"))
        XCTAssertFalse(w.cleanedFlags.first ?? true)
    }

    func testProviderFailureDegradesHonestly() async {
        let (p, w) = World.make(dir: try! makeDir())
        var pipeline = p
        var notices = 0
        pipeline.clean = { text in
            w.events.add("clean")
            return Cleaner.CleaningOutcome(text: text, applied: false, provider: nil)
        }
        pipeline.onCleanupUnavailable = { notices += 1 }
        let outcome = await pipeline.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(notices, 1, "a failed cleanup must be announced, never silent")
        XCTAssertEqual(w.pasted, ["hola mundo"], "raw text pasted on provider failure")
        XCTAssertFalse(w.cleanedFlags.first ?? true)
    }

    func testNakedCloudModeHasNoProviderAndNoNetworkPath() throws {
        // The root cause of P0-1: persisted "cloud" with NO key. Contract:
        // the mode records user INTENT, but the enforcement point is the
        // provider gate — no key means no provider, and the pipeline's
        // production default for `clean` is therefore nil (no network path).
        // (Cleaner.clean's own mode guard is unreachable through the flow.)
        let env = try TestEnvironment()
        defer { env.tearDown() }
        // V01-AC01: the QA root is never eager-created — this test owns its
        // config directory creation.
        try FileManager.default.createDirectory(at: env.paths.configFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "cleanup = \"cloud\"\n".write(to: env.paths.configFile, atomically: true, encoding: .utf8)
        let cfg = Config(paths: env.paths)
        XCTAssertFalse(cfg.hasCleanupProvider, "cloud intent without a key is not a provider")
        // The production seam default derives from this gate:
        XCTAssertNil(DictationPipeline.defaultClean(for: cfg))
    }

    // MARK: Learning gate

    func testLearningSkippedWhenPasteProducesNoSession() async {
        let (p, w) = World.make(dir: try! makeDir(), pasteReturnsSession: false)
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertTrue(w.learned.isEmpty)
        XCTAssertFalse(w.events.list.contains("learn"))
        XCTAssertEqual(w.events.list, ["resolve", "prompt", "transcribe", "rtf", "apply", "ax", "paste", "log"])
    }

    func testDisabledLearningSkipsOnlyLearningStep() async {
        let (p, w) = World.make(dir: try! makeDir(), learn: false)
        let outcome = await p.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(w.events.list, ["resolve", "prompt", "transcribe", "rtf", "apply", "ax", "paste", "log"])
        XCTAssertTrue(w.learned.isEmpty)
    }
}

extension TranscriptionError {
    /// Matches the pipeline's accessibility-denied failure message (D042 flow).
    static var accessibilityDeniedMessage: String {
        L.t("Accessibility permission needed for paste", es: "Falta permiso de Accesibilidad para pegar")
    }
}
