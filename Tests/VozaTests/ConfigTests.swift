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

    // MARK: P2-2 + P0-1 (audit 2026-09-21) — Config round-trip integrity

    func testGumroadPermalinkRoundTrips() throws {
        // P2-2: the value was persisted but never loaded — it evaporated on
        // every relaunch. The fix is in load(); the test writes the TOML
        // directly (the old setter was deleted as dead code in the
        // 2026-09-18 audit and stays dead — nothing in the app sets it).
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try FileManager.default.createDirectory(at: env.paths.configFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "gumroad_permalink = \"my-permalink_42\"\n".write(to: env.paths.configFile,
                                                              atomically: true, encoding: .utf8)
        let cfg = Config(paths: env.paths)
        XCTAssertEqual(cfg.gumroadPermalink, "my-permalink_42",
                       "a persisted permalink must survive construction")
        XCTAssertFalse(cfg.hasCleanupProvider, "QA env has no keys by construction")
    }

    func testHasCleanupProviderDetectsKeys() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try FileManager.default.createDirectory(at: env.paths.configFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "".write(to: env.paths.envFile, atomically: true, encoding: .utf8)
        var cfg = Config(paths: env.paths)
        XCTAssertFalse(cfg.hasCleanupProvider, "empty env → no provider")
        try "OPENAI_API_KEY=sk-test-123\n".write(to: env.paths.envFile, atomically: true, encoding: .utf8)
        cfg = Config(paths: env.paths)
        XCTAssertTrue(cfg.hasCleanupProvider, "an OpenAI key counts as a provider")
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
        config.setCleanupMode("cloud")

        let reloaded = Config(paths: env.paths)
        XCTAssertEqual(reloaded.resolvedLanguage, "es")
        XCTAssertTrue(reloaded.playSound)
        XCTAssertFalse(reloaded.autoLearn)
        XCTAssertEqual(reloaded.cleanupMode, "cloud")
        // File lives inside the QA root, nowhere else.
        XCTAssertTrue(env.paths.configFile.path.hasPrefix(env.root.path))
    }

    func testConfigDefaultsAreSane() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let config = Config(paths: env.paths)
        XCTAssertEqual(config.resolvedLanguage, "auto")
        XCTAssertTrue(config.autoLearn, "auto-learn is on by default (product decision)")
        XCTAssertEqual(config.cleanupMode, "plain", "D032: default never touches the network")
    }

    /// D032 privacy invariant, enforced at the setter: only "cloud" reaches
    /// the net; legacy local values ("auto"/"ollama"/"mlx") are clamped to
    /// "plain" — they can never resurrect removed local providers, and no
    /// stray value ever becomes an accidental network opt-in.
    func testCleanupModeClampingEnforcesPrivacyBoundary() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let config = Config(paths: env.paths)

        for legacy in ["auto", "ollama", "mlx", "", "CLOUD-CASE"] {
            config.setCleanupMode(legacy)
            XCTAssertEqual(config.cleanupMode, "plain",
                           "legacy/garbage value \(legacy) must clamp to plain")
        }
        config.setCleanupMode("cloud")
        XCTAssertEqual(config.cleanupMode, "cloud", "explicit opt-in is honored")
        // The clamped value is what persists.
        XCTAssertEqual(Config(paths: env.paths).cleanupMode, "cloud")
    }

    /// D032 provider chain: cloud-only, in fixed order. Pure boundary.
    func testProviderChainIsCloudOnly() {
        XCTAssertEqual(Cleaner.providerChain(for: "cloud"), ["openai", "anthropic"])
        XCTAssertTrue(Cleaner.providerChain(for: "plain").isEmpty)
        for legacy in ["auto", "ollama", "mlx"] {
            XCTAssertTrue(Cleaner.providerChain(for: legacy).isEmpty,
                          "legacy mode \(legacy) must not chain anywhere")
        }
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

    // MARK: - D032: cloud request contracts (pure seams)

    func testOpenAIRequestContract() {
        let req = Cleaner.openAIRequest(text: "hola mundo", apiKey: "sk-test",
                                        baseURL: nil, model: nil)
        let request = try! XCTUnwrap(req)
        XCTAssertEqual(request.url.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(request.body["model"] as? String, "gpt-4o-mini")
        // Prompt contract: system + user roles, temperature pinned for fidelity.
        let messages = try! XCTUnwrap(request.body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], Cleaner.systemPrompt)
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "hola mundo")
        XCTAssertEqual(request.body["temperature"] as? Double, 0.2)
    }

    func testAnthropicRequestContract() {
        let request = try! XCTUnwrap(
            Cleaner.anthropicRequest(text: "hola", apiKey: "sk-ant", model: nil))
        XCTAssertEqual(request.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "sk-ant")
        XCTAssertNotNil(request.headers["anthropic-version"])
        XCTAssertEqual(request.body["system"] as? String, Cleaner.systemPrompt)
    }

    func testStripThinkingJunk() {
        // Full think block → removed.
        XCTAssertEqual(Cleaner.stripThinkingJunk("<think>blah blah</think>\nTexto limpio."), "Texto limpio.")
        // Unclosed block (truncated reasoning) → drop everything from the tag.
        XCTAssertEqual(Cleaner.stripThinkingJunk("<think>razonamiento sin cerrar"), "")
        // Clean text → untouched.
        XCTAssertEqual(Cleaner.stripThinkingJunk("Hola mundo."), "Hola mundo.")
    }

    func testLevelBarsGeometry() {
        // Silence: near-minimum but never below 3pt (D022 compact HUD).
        for bar in 0..<4 {
            XCTAssertGreaterThanOrEqual(LevelBars.height(bar: bar, level: 0), 3)
            XCTAssertLessThanOrEqual(LevelBars.height(bar: bar, level: 1), 17)
        }
        // Level changes the output (reactivity contract).
        XCTAssertNotEqual(LevelBars.height(bar: 0, level: 0.2), LevelBars.height(bar: 0, level: 0.9))
    }

    func testHUDLevelDynamics() {
        // Fast attack: big jump toward a loud target.
        let attacked = HUDLevelModel.next(display: 0.0, target: 0.8)
        XCTAssertGreaterThan(attacked, 0.4)
        // Slow release: decays gently toward silence, never overshoots.
        let released = HUDLevelModel.next(display: 0.8, target: 0.0)
        XCTAssertGreaterThan(released, 0.6)
        XCTAssertLessThan(released, 0.8)
        // Converges to target.
        var d = 0.0
        for _ in 0..<200 { d = HUDLevelModel.next(display: d, target: 0.5) }
        XCTAssertEqual(d, 0.5, accuracy: 0.001)
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
