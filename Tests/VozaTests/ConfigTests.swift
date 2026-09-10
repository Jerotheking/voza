import XCTest
@testable import VozaKit

/// V02 — Rewritten to be hermetic (plan-glm). The old version called a
/// `recommendedModel()` overload that no longer existed (the suite had not
/// compiled since the V01 injection refactor — silent rot, exactly finding
/// F10), asserted stale RAM thresholds against the real machine, mutated the
/// global `L.override`, and appended markers to the user's ~/Dictation log.
final class ConfigTests: XCTestCase {
    func testCatalogHashesAreValidFormat() {
        for model in WhisperCatalog.all {
            XCTAssertEqual(model.sha256.count, 64, "bad hash for \(model.id)")
            XCTAssertTrue(model.sha256.allSatisfy { $0.isHexDigit }, "bad hash for \(model.id)")
            XCTAssertTrue(model.bytes > 1_000_000, "suspicious size for \(model.id)")
        }
    }

    // MARK: - recommendedModel (V02-AC01: parametrized, no reliance on real RAM)

    func testRecommendedModelByTierAndLanguage() {
        // ≥16 GB: large-v3-turbo regardless of language.
        for lang in ["en", "es", "auto"] {
            XCTAssertEqual(HardwareProfile.recommendedModel(language: lang, tier: .highRAM),
                           "large-v3-turbo", "lang=\(lang)")
        }
        // 8..<16 GB: fp16 small; English-only ONLY for explicit "en".
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "en", tier: .midRAM), "small.en")
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "es", tier: .midRAM), "small")
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "auto", tier: .midRAM), "small")
        // <8 GB: quantized builds; English-only ONLY for explicit "en".
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "en", tier: .lowRAM), "small.en-q5_1")
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "es", tier: .lowRAM), "small-q5_1")
        XCTAssertEqual(HardwareProfile.recommendedModel(language: "auto", tier: .lowRAM), "small-q5_1")
    }

    func testTierMapping() {
        XCTAssertEqual(HardwareProfile.RAMTier.tier(forRAMGB: 8), .midRAM)
        XCTAssertEqual(HardwareProfile.RAMTier.tier(forRAMGB: 15), .midRAM)
        XCTAssertEqual(HardwareProfile.RAMTier.tier(forRAMGB: 16), .highRAM)
        XCTAssertEqual(HardwareProfile.RAMTier.tier(forRAMGB: 96), .highRAM)
        XCTAssertEqual(HardwareProfile.RAMTier.tier(forRAMGB: 7), .lowRAM)
    }

    /// Audit v2 §3.2: non-English (and auto) must NEVER get an English-only
    /// model — for every tier, every multilingual language.
    func testMultilingualLanguagesNeverGetEnglishOnlyModels() {
        for tier in [HardwareProfile.RAMTier.highRAM, .midRAM, .lowRAM] {
            for lang in ["es", "auto", "fr", "de"] {
                let id = HardwareProfile.recommendedModel(language: lang, tier: tier)
                XCTAssertFalse(WhisperCatalog.byId(id)?.isEnglishOnly ?? true,
                               "\(lang) at \(tier) must not get English-only model \(id)")
            }
        }
    }

    // MARK: - Config roundtrip (QA environment, no real profile)

    func testConfigRoundtripAndResolution() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let config = Config(paths: env.paths)
        config.setLanguage("es")
        config.setPlaySound(true)
        config.setAutoLearn(false)
        config.setCleanupMode("ollama")

        let reloaded = Config(paths: env.paths)
        XCTAssertEqual(reloaded.resolvedLanguage, "es")
        XCTAssertTrue(reloaded.playSound)
        XCTAssertFalse(reloaded.autoLearn)
        XCTAssertEqual(reloaded.cleanupMode, "ollama")
        // File lives inside the QA root, nowhere else.
        XCTAssertTrue(env.paths.configFile.path.hasPrefix(env.root.path))
    }

    func testConfigDefaultsAreSane() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let config = Config(paths: env.paths)
        XCTAssertEqual(config.resolvedLanguage, "auto")
        XCTAssertTrue(config.autoLearn, "auto-learn is on by default (product decision)")
        XCTAssertEqual(config.cleanupMode, "auto")
    }

    // MARK: - D021: transcriber arguments + level meter (pure seams)

    func testTranscriptionArgumentsIncludeBeamSearchAndPrompt() {
        var args = Transcriber.transcriptionArguments(
            modelPath: "/m.bin", wavPath: "/a.wav", language: "auto", initialPrompt: "Tiago")
        args = Array(args.dropFirst()) // drop leading "-m"
        // Beam search 5 always present (D021 quality lever).
        if let i = args.firstIndex(of: "-bs") {
            XCTAssertEqual(args[args.index(after: i)], "5")
        } else {
            XCTFail("-bs 5 missing: Literal quality would regress to greedy decode")
        }
        // Learned-vocab prompt still forwarded.
        if let i = args.firstIndex(of: "--prompt") {
            XCTAssertEqual(args[args.index(after: i)], "Tiago")
        } else {
            XCTFail("--prompt missing: learned corrections would stop biasing decode")
        }
    }

    func testTranscriptionArgumentsOmitEmptyPrompt() {
        let args = Transcriber.transcriptionArguments(
            modelPath: "/m.bin", wavPath: "/a.wav", language: "es", initialPrompt: nil)
        XCTAssertFalse(args.contains("--prompt"))
    }

    func testMeterLevelMapping() {
        // −60 dB floor → 0; silence (0) → 0; loud (−6 dB ≈ 0.5 RMS) → 1.
        XCTAssertEqual(AudioRecorder.meterLevel(rms: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioRecorder.meterLevel(rms: 0.0001), 0, accuracy: 0.02)
        XCTAssertEqual(AudioRecorder.meterLevel(rms: 0.5), 1, accuracy: 0.001)
        // Scale midpoint: −33 dB ≈ 0.0224 RMS → 0.5 (−60 dB..−6 dB span 54 dB).
        XCTAssertEqual(AudioRecorder.meterLevel(rms: 0.0224), 0.5, accuracy: 0.02)
        // Monotonicity: louder input never yields a smaller bar.
        XCTAssertLessThan(AudioRecorder.meterLevel(rms: 0.01), AudioRecorder.meterLevel(rms: 0.1))
    }

    func testLevelBarsGeometry() {
        // Silence: near-minimum but never below 5pt.
        for bar in 0..<4 {
            XCTAssertGreaterThanOrEqual(LevelBars.height(bar: bar, level: 0), 5)
            XCTAssertLessThanOrEqual(LevelBars.height(bar: bar, level: 1), 22)
        }
        // Level changes the output (reactivity contract).
        XCTAssertNotEqual(LevelBars.height(bar: 0, level: 0.2), LevelBars.height(bar: 0, level: 0.9))
    }

    // MARK: - Localizer (pure + injected defaults; never the real domain)

    func testLocalizerPureResolution() {
        XCTAssertTrue(L.resolveIsSpanish(override: "es", systemLanguages: ["en"]))
        XCTAssertFalse(L.resolveIsSpanish(override: "en", systemLanguages: ["es-MX"]))
        XCTAssertTrue(L.resolveIsSpanish(override: nil, systemLanguages: ["es-MX", "en"]))
        XCTAssertFalse(L.resolveIsSpanish(override: nil, systemLanguages: ["en-US"]))
        XCTAssertFalse(L.resolveIsSpanish(override: nil, systemLanguages: nil))
        XCTAssertEqual(L.resolve("Hello", es: "Hola", spanish: true), "Hola")
        XCTAssertEqual(L.resolve("Hello", es: "Hola", spanish: false), "Hello")
    }

    func testLocalizerOverrideUsesInjectedSuiteOnly() {
        // V02: the old test wrote UserDefaults.standard — mutating the real
        // user preference domain from a test. Now: volatile suite, then gone.
        let suiteName = "voza.tests.localizer." + UUID().uuidString
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("volatile defaults suite unavailable")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }

        let before = UserDefaults.standard.string(forKey: "voza.language")
        L.defaultsSuite = suite
        defer { L.defaultsSuite = nil }

        L.override = "es"
        XCTAssertTrue(L.isSpanish)
        XCTAssertEqual(L.t("Hello", es: "Hola"), "Hola")
        L.override = "en"
        XCTAssertFalse(L.isSpanish)
        XCTAssertEqual(L.t("Hello", es: "Hola"), "Hello")

        XCTAssertEqual(UserDefaults.standard.string(forKey: "voza.language"), before,
                       "real preference domain was touched")
    }
}
