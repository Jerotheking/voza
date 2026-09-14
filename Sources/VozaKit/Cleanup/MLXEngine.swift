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

    private static let pressureSource = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical], queue: .global(qos: .utility))
    private nonisolated(unsafe) static var pressureInstalled = false

    // MARK: - Pure contract (hardening R4)

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
            let container = try await acquire(modelID: cfg.model.rawValue)
            // perform() serializes against load/evict inside the container's actor.
            let result = try await container.perform { context -> GenerateResult in
                let lmInput = try await context.processor.prepare(input: prompt)
                var parameters = GenerateParameters(temperature: cfg.temperature)
                parameters.maxTokens = cfg.maxTokens
                return try MLXLMCommon.generate(
                    input: lmInput, parameters: parameters, context: context) { _ in .more }
            }
            scheduleEviction(after: cfg.idleEvictionSeconds)
            // Defensive: never let a turn marker leak into the paste even if
            // a future model ignores the registered EOS (pure cut, tested).
            let cut = cutTurnMarker(result.output)
            guard !cut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Outcome(rawText: cut, generateSeconds: result.generateTime)
        } catch {
            // D024 debug visibility: a silent nil hides root causes. Logged,
            // never pasted. (Remove once the engine is proven in production.)
            print("[MLXEngine] error: \(error)")
            return nil
        }
    }

    /// Frees weights immediately (idle timer, memory pressure, Settings).
    public static func unloadNow() {
        lock.lock()
        container = nil
        loadedID = nil
        idleTask?.cancel()
        idleTask = nil
        lock.unlock()
        // Release the Metal buffer pool, not just the Swift references.
        GPU.clearCache()
    }

    /// True when weights are resident (Status/Settings surface).
    public static var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return container != nil
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
