import Foundation
import MLXLMCommon
import MLXLLM
import MLX

/// D024 — In-process cleanup engine (MLX). Replaces Ollama as the default
/// local Pulido path so adoption needs ONE download (the app): no daemon,
/// no port, no external base RSS.
///
/// RAM contract (D023/D024): weights live only while useful. Eviction is
/// ours — explicit unload, idle timer, and a memory-pressure source. Cleanup
/// runs after transcription (serial), so eviction never fights the STT
/// pipeline for Metal memory.
///
/// Hygiene contract: returns RAW model output. Applying
/// `Cleaner.stripThinkingJunk` is the CALLER's duty so the D023 rule
/// ("reasoning never reaches the paste") lives in exactly one place.
///
/// Model acquisition: HubApi (Hugging Face) on first use, cached in the
/// standard hub cache. Routing through ModelManager (SHA-256, QA
/// destinations) is a registered follow-up; not silently claimed here.
public enum MLXEngine {

    // MARK: - Model catalog (D024 tiers)

    public enum Model: String, CaseIterable, Sendable {
        /// Tier A — Apple Silicon ≥ 16 GB (owner's M4 Pro 24 GB). QAT variant:
        /// Google's quantization-aware training AND the only mlx-community
        /// text-only checkpoint whose config.json is complete — the plain
        /// `gemma-3-4b-it-4bit` omits num_attention_heads/head_dim and cannot
        /// load (verified: mismatchedSize q_proj 2048 vs 1024).
        case gemma4B = "mlx-community/gemma-3-4b-it-qat-4bit"
        /// Tier B — Apple Silicon 8 GB.
        case gemma2B = "mlx-community/gemma-3-2b-it-qat-4bit"
    }

    public struct Config: Sendable {
        public var model: Model = .gemma4B
        /// Idle seconds before weights are evicted (D023's 5 m contract).
        public var idleEvictionSeconds: TimeInterval = 300
        /// Latency ceiling per generation (D023: num_predict 400).
        public var maxTokens: Int = 400
        public var temperature: Float = 0.2
        /// D026 — TypeWhisper-style warm start: load weights from disk at
        /// launch (utility QoS) so the first Pulido costs generation time
        /// only, never the ~12 s cold load. Cached models only, never network.
        public var preloadOnLaunch = true
        /// D028 — mild loop-breaker for echo-prone cleaning tasks. nil keeps
        /// library default (no penalty).
        public var repetitionPenalty: Float? = 1.15
        /// D029 — hard wall-clock budget for ONE generation. The D028 guards
        /// only evaluate AFTER generation returns; a token loop at ~2 tok/s
        /// (or any stall) can grind for minutes before any post-hoc check
        /// runs (observed live 2026-09-14: 3 min truncated polish). The
        /// in-loop visitor enforces this ceiling and the engine falls back
        /// to raw (D016). nil disables (bench/bench-stress use).
        /// D030: 15 → 30 s. First live diagnosis showed cold generation
        /// AFTER load crawling (~33 s, 2 tokens — cold weight pages under
        /// heavy swap with another MLX model resident) while warm ran at
        /// ~8 s. 30 s keeps the never-hangs guarantee with 3.7× headroom
        /// over the degraded-warm baseline; the prewarm (below) targets
        /// the true cause of the cold crawl.
        public var maxGenerationSeconds: Double? = 30
        public init() {}
    }

    public static var config = Config()

    // MARK: - Result

    public struct Outcome: Sendable {
        /// RAW model output — caller applies Cleaner.stripThinkingJunk.
        public let rawText: String
        /// Generation wall time in seconds (excludes model load) — feeds
        /// PerformanceMonitor with real, comparable numbers.
        public let generateSeconds: Double
    }

    // MARK: - State (process-wide; cleanup is inherently serial)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var container: ModelContainer?
    private nonisolated(unsafe) static var loadedID: String?
    private nonisolated(unsafe) static var idleTask: Task<Void, Never>?
    /// In-flight generate/load count and a deferred-unload flag. Clearing the
    /// GPU cache under a running generation crashes Metal (observed live:
    /// EXC_BREAKPOINT via MLX's fatal default error handler), so unloads are
    /// deferred until the slot drains.
    private nonisolated(unsafe) static var inFlight = 0
    private nonisolated(unsafe) static var pendingUnload = false

    private static let pressureSource = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical], queue: .global(qos: .utility))
    private nonisolated(unsafe) static var pressureInstalled = false

    // MARK: - Pure contract (hardening R4)

    /// D028: generation consumed the ENTIRE token budget — the model never
    /// finished its answer (loop or genuinely long input). The output is
    /// truncated and must not be pasted as a "cleanup".
    static func hitTokenCeiling(tokenCount: Int, maxTokens: Int) -> Bool {
        tokenCount >= maxTokens
    }

    /// D029: wall-clock arm of the live tripwire — fired on EVERY generated
    /// token, the only place a stuck generation can be stopped while it is
    /// stuck. The D028 guards run only AFTER generation returns; the observed
    /// failure (2026-09-14) was a generation INSIDE the loop for minutes
    /// before any post-hoc check could run.
    static func generationTimedOut(elapsedSeconds: Double, maxSeconds: Double?) -> Bool {
        guard let maxSeconds else { return false }
        return elapsedSeconds > maxSeconds
    }

    /// D029: echo arm — the decoded window ends with the same `window` chars
    /// immediately repeated (verbatim overlap). A token loop signature, even
    /// when the machine is fast. Fast loops that reach the token ceiling are
    /// already caught post-hoc by `hitTokenCeiling`; this trips earlier and
    /// independent of `maxTokens`. `window` must be big enough that healthy
    /// prose (and short laughs) never overlaps verbatim with itself.
    static func echoLoopDetected(_ decodedTail: String, window: Int = 48) -> Bool {
        guard decodedTail.count >= 2 * window else { return false }
        let start2 = decodedTail.index(decodedTail.endIndex, offsetBy: -window)
        let start1 = decodedTail.index(start2, offsetBy: -window)
        return decodedTail[start1..<start2] == decodedTail[start2...]
    }

    /// Defensive cut of the Gemma turn marker. Registered-EOS should end
    /// generation there, but if a future checkpoint ignores it the marker must
    /// never leak into the paste. Pure so tests can pin it without Metal.
    static func cutTurnMarker(_ raw: String) -> String {
        guard let cut = raw.range(of: "<end_of_turn>").map({ String(raw[..<$0.lowerBound]) }) else { return raw }
        return cut
    }

    // MARK: - Public API

    /// Generates a cleanup completion for `text` given the system prompt.
    /// Returns nil when the engine cannot produce output — the caller falls
    /// back per D016 (raw transcript, honestly reported).
    public static func complete(_ text: String, systemPrompt: String) async -> Outcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        installPressureHandlerIfNeeded()

        let cfg = config
        let prompt = UserInput(chat: [
            .system(systemPrompt),
            .user(trimmed),
        ])

        do {
            // D029 live budget: the visitor runs on every token, so a loop or
            // a stall is cut at ~`maxGenerationSeconds` wall-clock (or a
            // verbatim echo overlap) instead of grinding for minutes before
            // the post-hoc guards can look. The visitor is invoked from the
            // generation loop inside a @Sendable closure — state crosses
            // concurrency domains, hence the locked box (Swift 6 clean).
            final class TripwireBox: @unchecked Sendable {
                private let lock = NSLock()
                private var tripped = false
                /// Which arm fired — wall-clock (slow/stuck) vs echo (loop at
                /// speed). Recorded at trip time so the log line is exact.
                private var reason = "unknown"
                var tripReason: (tripped: Bool, reason: String) {
                    lock.lock(); defer { lock.unlock() }
                    return (tripped, reason)
                }
                func trip(_ why: String) {
                    lock.lock()
                    if !tripped { reason = why }
                    tripped = true
                    lock.unlock()
                }
            }
            let box = TripwireBox()
            /// D029 amendment (first live diagnosis): the clock starts AFTER
            /// acquire — the budget governs GENERATION, not load. A cold
            /// first-install cleanup (download + ~12 s load) must not false-trip
            /// the 15 s budget the moment its tokens flow; contention like a
            /// competitor model resident on the same GPU slows the token stream
            /// itself, which is exactly what the budget exists to cut (observed:
            /// tripwall, 34.5 s, 2 tokens). Box-carried because the closure
            /// hierarchy crosses @Sendable boundaries.
            final class StartBox: @unchecked Sendable {
                let startedAt = Date()
                var elapsed: Double { Date().timeIntervalSince(startedAt) }
            }
            let clock = StartBox()
            let result = try await withEngineSlot {
                let container = try await acquire(modelID: cfg.model.rawValue)
                // perform() serializes against load/evict inside the container's actor.
                // withError converts C++ MLX errors into Swift throws — without a
                // scoped handler MLX's default handler calls fatalError (crash).
                return try await withError { error -> GenerateResult in
                    let r = try await container.perform { context -> GenerateResult in
                        let lmInput = try await context.processor.prepare(input: prompt)
                        var parameters = GenerateParameters(temperature: cfg.temperature)
                        parameters.maxTokens = cfg.maxTokens
                        // D028: a cleaning task that echoes the user's Spanish
                        // phrases can fall into token loops at low temperature;
                        // the loop grinds to the token ceiling and the paste
                        // arrives truncated after minutes (observed live). A
                        // mild penalty breaks loops without hurting fidelity.
                        parameters.repetitionPenalty = cfg.repetitionPenalty
                        return try MLXLMCommon.generate(
                            input: lmInput, parameters: parameters, context: context) { tokens in
                            let state = box.tripReason
                            if !state.tripped {
                                if MLXEngine.generationTimedOut(
                                    elapsedSeconds: clock.elapsed,
                                    maxSeconds: cfg.maxGenerationSeconds) {
                                    box.trip("wall")
                                } else {
                                    let tail = context.tokenizer.decode(tokens: Array(tokens.suffix(256)))
                                    if MLXEngine.echoLoopDetected(tail) {
                                        box.trip("echo")
                                    }
                                }
                            }
                            return state.tripped ? .stop : .more
                        }
                    }
                    try error.check()
                    return r
                }
            }
            scheduleEviction(after: cfg.idleEvictionSeconds)
            // D029: the live tripwire fired — generation was killed mid-flight
            // (wall-clock budget or verbatim echo loop). The partial output is
            // by definition unfinished: nil → D016 raw fallback, never a cut
            // paste. Logged for diagnosis.
            if box.tripReason.tripped {
                let elapsed = clock.elapsed
                // D029: which arm fired matters — wall-clock means slow/stuck,
                // echo means a loop even at speed. Both fall back to raw.
                let state = box.tripReason
                let event = state.reason == "wall" ? "tripwall" : "tripecho"
                print("[MLXEngine] tripwire: stopped at \(result.tokens.count) tokens, " +
                      String(format: "%.1fs", elapsed) + " — falling back to raw")
                CleanupLog.write("mlx", event, seconds: elapsed,
                                 detail: "tokens=\(result.tokens.count) fallback=raw")
                return nil
            }
            // Defensive: never let a turn marker leak into the paste even if
            // a future model ignores the registered EOS (pure cut, tested).
            let cut = cutTurnMarker(result.output)
            guard !cut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            // D028: ceiling-hit truncation guard. If generation consumed the
            // whole token budget, the model never finished its answer — the
            // output is cut mid-sentence. Return nil so the caller pastes the
            // raw transcript (D016) instead of a truncated "cleanup".
            if hitTokenCeiling(tokenCount: result.tokens.count, maxTokens: cfg.maxTokens) {
                let msg = "ceiling hit: \(result.tokens.count) tokens in " +
                          String(format: "%.1fs — treating as truncated", result.generateTime)
                print("[MLXEngine] \(msg)")
                CleanupLog.write("mlx", "ceiling", seconds: result.generateTime,
                                 detail: "tokens=\(result.tokens.count) fallback=raw")
                return nil
            }
            return Outcome(rawText: cut, generateSeconds: result.generateTime)
        } catch {
            // D027: errors from MLX land here (withError). Logged, never
            // pasted; the caller falls back to the raw transcript.
            print("[MLXEngine] error: \(error)")
            CleanupLog.write("mlx", "error", detail: "\(error) — fallback=raw")
            return nil
        }
    }

    /// Frees weights immediately (idle timer, memory pressure, Settings).
    /// Skips the GPU call when nothing is resident — clearing an empty cache
    /// must not initialize Metal (test runners have no metallib colocated).
    /// NEVER clears the GPU cache while a generate/load is in flight — that
    /// is the crash from 2026-09-14; the unload is deferred to slot exit.
    // MARK: - Unload deferral state machine (pure, stress-tested)

    /// Pure decision table for `unloadNow` (D027): what may be cleared given
    /// residency and engine activity. While a generate/load is in flight the
    /// GPU cache must NEVER be touched — clearing Metal under running kernels
    /// crashes (observed live 2026-09-14); the intent is recorded and the
    /// engine slot flushes it on exit.
    static func unloadPlan(hasWeights: Bool, inFlight: Int)
        -> (clearStore: Bool, clearGPU: Bool, deferUnload: Bool) {
        if inFlight > 0 {
            return (false, false, hasWeights)
        }
        return (true, hasWeights, false)
    }

    /// Pure: whether a drained engine slot must flush a deferred unload.
    static func slotExitFlush(inFlight: Int, pendingUnload: Bool) -> Bool {
        inFlight == 0 && pendingUnload
    }

    public static func unloadNow() {
        lock.lock()
        let plan = unloadPlan(hasWeights: container != nil, inFlight: inFlight)
        if plan.deferUnload {
            pendingUnload = true
            lock.unlock()
            return
        }
        container = nil
        loadedID = nil
        idleTask?.cancel()
        idleTask = nil
        pendingUnload = false
        lock.unlock()
        // Release the Metal buffer pool, not just the Swift references.
        guard plan.clearGPU else { return }
        GPU.clearCache()
    }

    /// Sync helpers: lock is never held across an await (Swift 6 safe).
    private static func enterSlot() {
        lock.lock(); inFlight += 1; lock.unlock()
    }

    /// Returns true when this exit must flush a deferred unload.
    private static func exitSlot() -> Bool {
        lock.lock(); inFlight -= 1
        let flush = slotExitFlush(inFlight: inFlight, pendingUnload: pendingUnload)
        if flush { pendingUnload = false }
        lock.unlock()
        return flush
    }

    /// Marks an engine operation (generate/load) as in flight. Unload
    /// requests arriving meanwhile are deferred and flushed on slot exit.
    private static func withEngineSlot<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        enterSlot()
        defer {
            if exitSlot() { unloadNow() }
        }
        return try await body()
    }

    /// True when weights are resident (Status/Settings surface).
    public static var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return container != nil
    }

    /// D026 — TypeWhisper-style warm start. Loads weights from disk into the
    /// GPU at launch so the first Pulido pays generation time only (~0.8 s
    /// warm), never the ~12 s cold load. Contract: NEVER touches the network
    /// — a model not present in the MLXLMCommon cache is skipped and the
    /// first cleanup downloads as before. Fire-and-forget; the idle-eviction
    /// clock is NOT started here (a user who never dictes must not pay RAM).
    /// D030: additionally runs a mini-generation so the first real cleanup
    /// is warm-speed (see warmupGeneration).
    public static func preloadNow(modelExists: ((String) -> Bool)? = nil) async {
        guard config.preloadOnLaunch, !isLoaded else { return }
        let id = config.model.rawValue
        let exists = modelExists.map { $0(id) } ?? defaultCachedModelExists(id)
        guard exists else { return }
        // Pressure handler must also cover preload-only residency: weights
        // loaded at launch are released under system memory pressure even
        // if the user never dictates (D026 RAM contract). unloadNow defers
        // itself while a load is in flight (crash guard).
        installPressureHandlerIfNeeded()
        _ = try? await withEngineSlot {
            try await withError { error -> ModelContainer in
                let c = try await acquire(modelID: id)
                // D030 prewarm: touching every weight page ONCE at launch
                // (background, user is not waiting) converts the first real
                // cleanup from ~33 s cold-crawl to warm speed. A warmup
                // failure must never fail the preload itself.
                if let warmSeconds = try? await warmupGeneration(container: c) {
                    CleanupLog.write("mlx", "prewarm", seconds: warmSeconds,
                                     detail: "launch warmup")
                }
                try error.check()
                return c
            }
        }
    }

    /// D030 — mini-generation that exercises every layer at preload time.
    /// The first token pass sweeps ALL weights (plus shader compilation),
    /// which is exactly the work the first real cleanup was paying under
    /// memory pressure (observed: tripwall at 33 s for 2 tokens, then warm
    /// at 7.9 s). Budget intentionally disabled: this is launch-time
    /// background work, not user-facing latency.
    private static func warmupGeneration(container: ModelContainer) async throws -> Double {
        let t0 = Date()
        let input = UserInput(chat: [.system("Warmup."), .user("hi")])
        _ = try await container.perform { context -> GenerateResult in
            let lmInput = try await context.processor.prepare(input: input)
            var parameters = GenerateParameters(temperature: 0.0)
            parameters.maxTokens = 4
            parameters.repetitionPenalty = nil
            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context) { _ in .more }
        }
        return Date().timeIntervalSince(t0)
    }

    /// Mirrors MLXLMCommon's `defaultHubApi` layout: cachesDirectory/models/
    /// {org}/{repo}. Present only if the weights file exists — a metadata-only
    /// directory is not loadable and must not count as cached.
    public static func defaultCachedModelExists(_ modelID: String) -> Bool {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return false }
        let parts = modelID.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return false }
        let weights = caches
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent("model.safetensors")
        return FileManager.default.fileExists(atPath: weights.path)
    }

    // MARK: - Internals

    private static func acquire(modelID: String) async throws -> ModelContainer {
        if let c = cachedContainer(for: modelID) { return c }
        // Gemma's turn-end marker is an EOS in the checkpoint's
        // generation_config but is NOT registered by the library for this
        // repo id (only the 1B QAT entry carries it). Without it, generation
        // burns the full maxTokens ceiling emitting <end_of_turn> spam.
        let configuration = ModelConfiguration(
            id: modelID,
            extraEOSTokens: ["<end_of_turn>"])
        let c = try await MLXLMCommon.loadModelContainer(configuration: configuration)
        storeContainer(c, id: modelID)
        return c
    }

    /// Sync helper: lock is never held across an await (Swift 6 safe).
    private static func cachedContainer(for modelID: String) -> ModelContainer? {
        lock.lock(); defer { lock.unlock() }
        return container.flatMap { loadedID == modelID ? $0 : nil }
    }

    /// Sync helper: store after successful load. Returns the final resident
    /// container (callers race rarely — cleanup is serial — last write wins
    /// and the loser's weights are released by eviction or next unload).
    private static func storeContainer(_ c: ModelContainer, id: String) {
        lock.lock(); defer { lock.unlock() }
        container = c
        loadedID = id
    }

    private static func scheduleEviction(after seconds: TimeInterval) {
        replaceIdleTask(Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            unloadNow()
        }, after: seconds)
    }

    /// Sync helper: cancel-then-store without holding the lock over awaits.
    private static func replaceIdleTask(_ task: Task<Void, Never>, after seconds: TimeInterval) {
        lock.lock()
        idleTask?.cancel()
        idleTask = task
        lock.unlock()
    }

    private static func installPressureHandlerIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !pressureInstalled else { return }
        pressureInstalled = true
        pressureSource.setEventHandler { unloadNow() }
        pressureSource.resume()
    }
}
