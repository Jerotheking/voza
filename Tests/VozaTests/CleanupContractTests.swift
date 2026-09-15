import XCTest
@testable import VozaKit

/// Hardening R1+R2+R4 (docs/plan-glm/evidence/coverage-gap-report.md).
///
/// Pins the text contracts of the Pulido pipeline — the artifacts that three
/// owner-driven debugging sessions produced and no live probe can guard
/// permanently: the cleaner system prompt (R1), the cloud request/response
/// contracts (R2) and MLXEngine's pure surfaces (R4). All hermetic: no
/// network, no Metal, no disk.
final class CleanupContractTests: XCTestCase {

    // MARK: - R1: system prompt invariants

    /// Rule 3 encodes the spoken self-edit feature (owner session 2026-09-11:
    /// "…y quita lo de cómo funciona" was being pasted verbatim). Every named
    /// command form must stay in the prompt for the model to apply-and-drop it.
    func testPromptDefinesEditCommands() {
        let p = Cleaner.systemPrompt
        for phrase in ["quita lo de X", "quita eso", "borra lo último", "no, di mejor X"] {
            XCTAssertTrue(p.contains(phrase), "edit-command rule lost phrase: \(phrase)")
        }
        XCTAssertTrue(p.contains("NEVER output the command itself"),
                      "prompt must demand applying AND dropping the command")
    }

    /// Rule 2 + rule 4: filler removal exists, but rewriting/translating is
    /// forbidden — the cleaner must never become a ghostwriter.
    func testPromptPreservesLanguageAndMeaning() {
        let p = Cleaner.systemPrompt
        XCTAssertTrue(p.contains("filler"), "filler-removal rule missing")
        XCTAssertTrue(p.contains("Keep the speaker's language, meaning and tone"))
        XCTAssertTrue(p.contains("Do not rewrite, translate or add anything"))
    }

    /// Rule 1: capitalization instruction — the short-sentence slip found
    /// while validating the edit-command rule ("esta es" kept lowercase).
    func testPromptRequiresSentenceCapitalization() {
        XCTAssertTrue(Cleaner.systemPrompt
            .contains("always capitalize the first word of the text and of each sentence"))
    }

    /// Output hygiene: no quotes, no commentary — the "We are given a text…"
    /// meta-commentary failure mode (qwen3 era, D023).
    func testPromptForbidsCommentary() {
        XCTAssertTrue(Cleaner.systemPrompt.contains("Output ONLY the cleaned text"))
    }

    /// The prompt travels inside EVERY provider request — a provider whose
    /// body drops it silently cleans without the contract.
    func testPromptTravelsInEveryRequest() {
        let openai = Cleaner.openAIRequest(text: "t", apiKey: "k", baseURL: nil, model: nil)!
        XCTAssertTrue((openai.body["messages"] as? [[String: Any]])?.contains {
            ($0["role"] as? String) == "system" && ($0["content"] as? String) == Cleaner.systemPrompt
        } ?? false)
        let anthropic = Cleaner.anthropicRequest(text: "t", apiKey: "k", model: nil)!
        XCTAssertEqual(anthropic.body["system"] as? String, Cleaner.systemPrompt)
        let ollama = Cleaner.ollamaRequestBody(text: "t", model: "m", keepAlive: "5m")
        XCTAssertTrue((ollama["messages"] as? [[String: Any]])?.contains {
            ($0["role"] as? String) == "system" && ($0["content"] as? String) == Cleaner.systemPrompt
        } ?? false)
    }

    // MARK: - R2: cloud request contracts

    func testOpenAIRequestDefaultsAndAuth() throws {
        let req = try XCTUnwrap(Cleaner.openAIRequest(text: "hola", apiKey: "sk-test",
                                                      baseURL: nil, model: nil))
        XCTAssertEqual(req.url.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(req.headers["Content-Type"], "application/json")
        XCTAssertEqual(req.body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(req.body["temperature"] as? Double, 0.2)
    }

    /// CLEANUP_MODEL override and OPENAI_BASE_URL for OpenRouter/Groq/LM Studio.
    func testOpenAIRequestOverrides() throws {
        let req = try XCTUnwrap(Cleaner.openAIRequest(text: "hola", apiKey: "k",
                                                      baseURL: "https://openrouter.ai/api/v1/",
                                                      model: "llama-3.1-8b"))
        XCTAssertEqual(req.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(req.body["model"] as? String, "llama-3.1-8b")
    }

    /// A base URL of only slashes (or empty) must fall back to the default —
    /// never emit a relative "…/chat/completions" that URL(string:) accepts
    /// and URLSession then fails on at call time.
    func testOpenAIRequestSlashOnlyBaseURLFallsBackToDefault() throws {
        let req = try XCTUnwrap(Cleaner.openAIRequest(text: "hola", apiKey: "k",
                                                      baseURL: "///", model: nil))
        XCTAssertEqual(req.url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testAnthropicRequestContract() throws {
        let req = try XCTUnwrap(Cleaner.anthropicRequest(text: "hola", apiKey: "ak-test",
                                                         model: nil))
        XCTAssertEqual(req.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.headers["x-api-key"], "ak-test")
        XCTAssertEqual(req.headers["anthropic-version"], "2023-06-01")
        XCTAssertEqual(req.body["max_tokens"] as? Int, 2048)
        XCTAssertEqual(req.body["model"] as? String, "claude-3-5-haiku-latest")
    }

    func testParseOpenAIResponse() throws {
        let happy = #"{"choices":[{"message":{"content":"  Hola, mundo.  "}}]}"#
        XCTAssertEqual(try XCTUnwrap(Cleaner.parseOpenAIResponse(Data(happy.utf8))),
                       "Hola, mundo.")
        // Empty/missing content → nil → D016 fallback to raw transcript.
        XCTAssertNil(Cleaner.parseOpenAIResponse(Data(#"{"choices":[]}"#.utf8)))
        XCTAssertNil(Cleaner.parseOpenAIResponse(Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)))
        XCTAssertNil(Cleaner.parseOpenAIResponse(Data("not json".utf8)))
    }

    func testParseAnthropicResponse() throws {
        // Multiple text blocks join in order (SSE-style chunked answers).
        let valid = #"{"content":[{"type":"text","text":"Hola, "},{"type":"text","text":"mundo."}]}"#
        XCTAssertEqual(try XCTUnwrap(Cleaner.parseAnthropicResponse(Data(valid.utf8))),
                       "Hola, mundo.")
        // Non-text blocks are skipped, empty result → nil.
        XCTAssertNil(Cleaner.parseAnthropicResponse(Data(#"{"content":[{"type":"tool_use"}]}"#.utf8)))
        XCTAssertNil(Cleaner.parseAnthropicResponse(Data("".utf8)))
    }

    // MARK: - R4: MLXEngine pure surfaces

    /// Registered EOS should end generation; if a future checkpoint ignores
    /// it, the marker must never leak into the paste (measured defect: 400
    /// tokens of "<end_of_turn>" spam, D024).
    func testCutTurnMarker() {
        XCTAssertEqual(MLXEngine.cutTurnMarker("Hola, mundo."), "Hola, mundo.")
        XCTAssertEqual(MLXEngine.cutTurnMarker("Hola, mundo.<end_of_turn>spam"),
                       "Hola, mundo.")
        XCTAssertEqual(MLXEngine.cutTurnMarker("<end_of_turn>"), "")
    }

    /// D023/D024 registered limits live in the config defaults: a silent
    /// change here re-opens the RAM or latency budgets.
    func testMLXConfigDefaultsMatchRegisteredDecisions() {
        let cfg = MLXEngine.Config()
        XCTAssertEqual(cfg.maxTokens, 400, "D023 latency ceiling (num_predict)")
        XCTAssertEqual(cfg.idleEvictionSeconds, 300, "D023 5-minute RAM residency")
        XCTAssertEqual(cfg.temperature, 0.2, accuracy: 0.0001)
    }

    /// The checkpoint IDs are network contracts (HubApi download). The 4B QAT
    /// is also the only mlx-community text-only checkpoint with a complete
    /// config.json (plain 4b crashes: q_proj 2048 vs 1024, measured D024).
    func testMLXModelIdentifiers() {
        XCTAssertEqual(MLXEngine.Model.gemma4B.rawValue,
                       "mlx-community/gemma-3-4b-it-qat-4bit")
        XCTAssertEqual(MLXEngine.Model.gemma2B.rawValue,
                       "mlx-community/gemma-3-2b-it-qat-4bit")
        for m in MLXEngine.Model.allCases {
            XCTAssertTrue(m.rawValue.hasPrefix("mlx-community/"), "unexpected hub org: \(m.rawValue)")
        }
    }

    // MARK: - D027 stress contract: unload deferral state machine (pure)

    /// The decision table that prevented the 2026-09-14 crash: the GPU cache
    /// is NEVER cleared while a generate/load is in flight.
    func testUnloadPlanDefersWhileEngineBusy() {
        // Busy + resident: nothing cleared, unload intent recorded.
        let busy = MLXEngine.unloadPlan(hasWeights: true, inFlight: 1)
        XCTAssertFalse(busy.clearStore, "store must survive until the slot drains")
        XCTAssertFalse(busy.clearGPU, "clearing Metal under running kernels is the crash")
        XCTAssertTrue(busy.deferUnload)
        // Busy + empty: nothing to do, nothing deferred.
        let busyEmpty = MLXEngine.unloadPlan(hasWeights: false, inFlight: 2)
        XCTAssertFalse(busyEmpty.deferUnload)
        XCTAssertFalse(busyEmpty.clearGPU)
        // Idle + resident: full clear (normal eviction path).
        let idle = MLXEngine.unloadPlan(hasWeights: true, inFlight: 0)
        XCTAssertTrue(idle.clearStore)
        XCTAssertTrue(idle.clearGPU)
        XCTAssertFalse(idle.deferUnload)
        // Idle + empty: store reset is harmless, GPU untouched — Metal must
        // never initialize just to unload nothing (test-runner contract).
        let idleEmpty = MLXEngine.unloadPlan(hasWeights: false, inFlight: 0)
        XCTAssertTrue(idleEmpty.clearStore)
        XCTAssertFalse(idleEmpty.clearGPU)
    }

    /// A drained slot flushes exactly the deferred intent, nothing else.
    func testSlotExitFlushRules() {
        XCTAssertFalse(MLXEngine.slotExitFlush(inFlight: 1, pendingUnload: true),
                       "other operations still in flight")
        XCTAssertFalse(MLXEngine.slotExitFlush(inFlight: 0, pendingUnload: false),
                       "nothing was deferred")
        XCTAssertTrue(MLXEngine.slotExitFlush(inFlight: 0, pendingUnload: true))
    }

    // MARK: - D028: truncation guards (the live 3-minute-truncated polish)

    /// Generation consuming the whole budget = unfinished answer = truncated
    /// paste. Must fall back to raw, never ship a half cleanup.
    func testTokenCeilingDetection() {
        XCTAssertTrue(MLXEngine.hitTokenCeiling(tokenCount: 400, maxTokens: 400))
        XCTAssertTrue(MLXEngine.hitTokenCeiling(tokenCount: 401, maxTokens: 400))
        XCTAssertFalse(MLXEngine.hitTokenCeiling(tokenCount: 399, maxTokens: 400))
        XCTAssertFalse(MLXEngine.hitTokenCeiling(tokenCount: 0, maxTokens: 400))
    }

    /// The loop-breaker default is set (echo-prone task + low temperature =
    /// loop risk, measured live) and the config knob remains overridable.
    func testRepetitionPenaltyDefault() {
        var cfg = MLXEngine.Config()
        XCTAssertEqual(cfg.repetitionPenalty ?? 0, 1.15, accuracy: 0.0001,
                       "mild penalty must be the default for the cleaning task")
        cfg.repetitionPenalty = nil // power users can disable
        XCTAssertNil(cfg.repetitionPenalty)
    }

    // MARK: - D029: live generation tripwire (the stuck-polish thread)

    /// The live wall-clock budget is on by default: the D028 guards only run
    /// AFTER generation returns, but the observed failure was a generation
    /// stuck INSIDE the loop for minutes. Someone must stop it mid-flight.
    /// D030: raised to 30 s after the first live diagnosis — cold generation
    /// under swap+GPU-contention crawled at ~33 s/2 tokens while warm ran
    /// ~8 s; 15 s false-tripped degraded-but-working machines.
    func testLiveGenerationBudgetDefault() {
        let cfg = MLXEngine.Config()
        XCTAssertEqual(cfg.maxGenerationSeconds ?? 0, 30, accuracy: 0.0001,
                       "hard wall-clock budget must be the default")
    }

    /// Wall-clock arm: past budget → stop. This is the arm that kills the
    /// observed 3-minute stuck polish: it fires WHILE the generation runs,
    /// not after it finally returns. (Boundary is >: budget-exact is not
    /// tripped — a machine at exactly 30 s of honest work still pastes.)
    func testTripwireWallClock() {
        XCTAssertTrue(MLXEngine.generationTimedOut(elapsedSeconds: 30.1, maxSeconds: 30))
        XCTAssertFalse(MLXEngine.generationTimedOut(elapsedSeconds: 29.9, maxSeconds: 30))
        XCTAssertFalse(MLXEngine.generationTimedOut(elapsedSeconds: 30, maxSeconds: 30))
        // Disabled budget (nil) never trips on time alone (bench mode).
        XCTAssertFalse(MLXEngine.generationTimedOut(elapsedSeconds: 10_000, maxSeconds: nil))
    }

    /// Echo arm: the tail overlaps itself verbatim — a token loop signature,
    /// even when the machine is fast and the ceiling is far away.
    func testTripwireEchoLoop() {
        // Period 12 divides window 48 → halves align exactly, as a real token
        // loop does after enough tokens.
        let looped = String(repeating: "y te digo q ", count: 8) // 96 = 2×48
        XCTAssertTrue(MLXEngine.echoLoopDetected(looped))
        // Healthy prose: halves differ, no verbatim overlap.
        XCTAssertFalse(MLXEngine.echoLoopDetected(
            "Hola, esto es una prueba de dictado normal que avanza sin repetirse.",
            window: 12))
        // Too short to compare: no verdict.
        XCTAssertFalse(MLXEngine.echoLoopDetected("corta", window: 48))
        // Exactly 2×window with distinct halves: not a loop.
        XCTAssertFalse(MLXEngine.echoLoopDetected(
            String(repeating: "a", count: 47) + "b" + String(repeating: "c", count: 48),
            window: 48))
        // Pathological but real: pure repetition of one syllable IS a loop.
        XCTAssertTrue(MLXEngine.echoLoopDetected(String(repeating: "ja", count: 60)))
    }

    /// Healthy generation never trips on time: normal speed, inside budget.
    func testTripwireLeavesHealthyGenerationAlone() {
        XCTAssertFalse(MLXEngine.generationTimedOut(elapsedSeconds: 2.1, maxSeconds: 15))
    }

    // MARK: - D031: starvation arm + reload gate

    /// Starvation arm: past the 8 s window with <5 total tokens = GPU
    /// starved — cut early instead of paying the full wall-clock budget.
    func testProgressStarvedCutsDegradedGeneration() {
        // The observed live incident: 2 tokens after 8 s → starved.
        XCTAssertTrue(MLXEngine.progressStarved(tokensSoFar: 2, elapsedSeconds: 8.1))
        XCTAssertTrue(MLXEngine.progressStarved(tokensSoFar: 0, elapsedSeconds: 30))
        // Boundary inclusive: exactly at the window with too few tokens.
        XCTAssertTrue(MLXEngine.progressStarved(tokensSoFar: 4, elapsedSeconds: 8))
        // Healthy warm generation (~40 tok/s): way past 5 tokens by second 8.
        XCTAssertFalse(MLXEngine.progressStarved(tokensSoFar: 6, elapsedSeconds: 8))
        XCTAssertFalse(MLXEngine.progressStarved(tokensSoFar: 300, elapsedSeconds: 25))
        // Inside the window: no verdict yet — give the model its 8 s.
        XCTAssertFalse(MLXEngine.progressStarved(tokensSoFar: 1, elapsedSeconds: 7.9))
        // Progress-then-stall is NOT this arm's job: 50 tokens then stalled
        // still has tokensSoFar ≥ 5; the wall arm owns it.
        XCTAssertFalse(MLXEngine.progressStarved(tokensSoFar: 50, elapsedSeconds: 29))
    }

    /// Reload gate: exact requirement passes, anything below fails — and the
    /// names stay pinned so a silent constant change cannot slip past review.
    func testReloadGateAndConstants() {
        XCTAssertTrue(MLXEngine.reloadAvailable(availableMB: 3584, requiredMB: 3584))
        XCTAssertTrue(MLXEngine.reloadAvailable(availableMB: 4000, requiredMB: 3584))
        XCTAssertFalse(MLXEngine.reloadAvailable(availableMB: 3583.9, requiredMB: 3584))
        // Contract constants (D031) — changing these silently breaks either
        // latency (too tight) or protection (too loose).
        XCTAssertEqual(MLXEngine.starvationWindowSeconds, 8, accuracy: 0.0001)
        XCTAssertEqual(MLXEngine.starvationMinTokens, 5)
        XCTAssertEqual(MLXEngine.reloadRequiredMB, 3584, accuracy: 0.0001)
    }

    /// The metrics helper returns a plausible figure or nil — never crashes,
    /// never a negative. (The gate itself fails open on nil: tested above.)
    func testSystemMemoryAvailableMBIsPlausible() {
        if let mb = MLXEngine.SystemMemory.availableMB() {
            XCTAssertGreaterThanOrEqual(mb, 0)
            XCTAssertLessThan(mb, 262_144, "free+inactive above 256 GB is implausible")
        }
        // nil is a legitimate outcome (kernel API failure) — no assertion.
    }
}
