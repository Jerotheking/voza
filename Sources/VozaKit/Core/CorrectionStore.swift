import Foundation

/// One learned correction: what Voza heard → what the user actually meant.
/// Immutable value type; identity is (heard, said), so re-recording the same
/// heard phrase updates the entry instead of duplicating it.
struct Correction: Identifiable, Hashable, Codable {
    let id: UUID
    let heard: String
    let said: String
    let createdAt: Date
}

/// Vocabulary learned from the user's own corrections (product decision
/// registered 2026-09-08: "el que lee y sube la importancia" — promoted ahead
/// of V31's full VocabularyStore).
///
/// Two consumers:
/// 1. **Exact replacement** — post-transcription word-boundary substitution of
///    a heard phrase by its approved correction (source of truth for what was
///    pasted).
/// 2. **Model conditioning** — the correction phrases seed whisper.cpp's
///    `--prompt` so the model is biased toward the user's real vocabulary
///    (names, brands, terms it keeps mishearing) BEFORE it decodes.
///
/// Fully local (JSON under the injected app-support dir), zero telemetry.
/// Follows the V01 injection pattern: paths + clock are constructor
/// dependencies; construction and reads create nothing on disk (writes
/// create/prepare the file lazily). All mutable state is confined to a serial
/// queue, like TranscriptStore.
final class CorrectionStore {
    static let shared = CorrectionStore()

    private let queue = DispatchQueue(label: "voza.correctionstore")
    private let paths: AppPaths
    private let clock: Clock
    /// In-memory mirror, guarded by `queue`. Main-thread UI reads go through
    /// `all()` which hops onto the queue synchronously.
    private var cached: [Correction] = []
    private var loaded = false

    /// Correction file inside the injected app-support tree.
    var correctionsFile: URL { paths.appSupport.appendingPathComponent("corrections.json") }

    init(paths: AppPaths = .default, clock: Clock = SystemClock()) {
        self.paths = paths
        self.clock = clock
    }

    // MARK: - API

    /// All corrections, most recently created first. Blocking call on the
    /// serial queue; the file is small (user-approved entries only), and UI
    /// callers are already on the main thread showing a popover.
    func all() -> [Correction] {
        queue.sync {
            loadIfNeededLocked()
            return cached.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Count above which replacement stops being applied (prompt conditioning
    /// remains, capped separately). UI can show this in the future.
    var count: Int { all().count }

    /// Records or updates a correction: heard → said. If the same `heard`
    /// exists, its `said` is updated (kept at its original creation date so
    /// ordering stays stable). Returns the stored entry.
    ///
    /// Length caps mirror `CorrectionWatcher.maxLearnedChars`: `record` is the
    /// ONE chokepoint both learning paths flow through, so the guard lives
    /// here, not in the callers. A cap here protects BOTH consumers — the
    /// word-boundary replacer (a 350-char "phrase" can never fire safely)
    /// and the whisper prompt budget (one oversized `said` would consume the
    /// entire 200-char conditioning budget and starve the real vocabulary).
    /// (D033: the manual ✏️ path had no cap and poisoned a real store.)
    @discardableResult
    func record(heard: String, said: String) -> Correction? {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !s.isEmpty, h != s else { return nil }
        guard h.count <= CorrectionWatcher.maxLearnedChars,
              s.count <= CorrectionWatcher.maxLearnedChars else { return nil }
        // Same letter shape on a single token ("tiago" → "Tiago"): the
        // watcher's `valid` guard rejects these as dead weight, and so does
        // the chokepoint — otherwise the manual ✏️ path would re-admit them.
        if h.lowercased() == s.lowercased(), !h.contains(" "), !s.contains(" ") {
            return nil
        }
        return queue.sync {
            loadIfNeededLocked()
            let now = clock.now
            // Case-insensitive dedupe: "Sintelia" and "sintelia" are the
            // same key for the replacer (it lowercases), so two entries would
            // be UI noise and double prompt budget for one term.
            if let idx = cached.firstIndex(where: { $0.heard.lowercased() == h.lowercased() }) {
                let updated = Correction(id: cached[idx].id, heard: h, said: s, createdAt: cached[idx].createdAt)
                cached[idx] = updated
                persistLocked()
                return updated
            }
            let entry = Correction(id: UUID(), heard: h, said: s, createdAt: now)
            cached.append(entry)
            persistLocked()
            return entry
        }
    }

    /// Deletes one correction (lets the user undo a bad edit).
    func delete(id: UUID) {
        queue.sync {
            loadIfNeededLocked()
            cached.removeAll { $0.id == id }
            persistLocked()
        }
    }

    // MARK: - Consumer 1: exact replacement

    /// Applies learned corrections to a transcript in ONE pass: a combined
    /// regex alternation (longest phrases first, so "tiago rey" wins over
    /// "tiago" at the same position) means inserted replacements are never
    /// re-scanned — an early short correction cannot cannibalize a longer
    /// one's result. Word-boundary, case-insensitive on the heard side;
    /// replacement preserves the case pattern (ALL CAPS heard text stays ALL
    /// CAPS). Empty store returns the input unchanged. Pure static so tests
    /// need no disk at all.
    static func apply(_ text: String, corrections: [Correction]) -> String {
        guard !corrections.isEmpty else { return text }
        var saidByHeard: [String: String] = [:]
        var phrases: [String] = []
        for c in corrections {
            let key = c.heard.lowercased()
            if saidByHeard[key] == nil { phrases.append(c.heard) }
        }
        guard !phrases.isEmpty else { return text }
        let alternation = phrases
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:\(alternation))\\b", options: [.caseInsensitive]) else { return text }
        for c in corrections { saidByHeard[c.heard.lowercased()] = c.said }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: full)
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let heardMatch = ns.substring(with: m.range)
            let said = saidByHeard[heardMatch.lowercased()] ?? heardMatch
            result += matchingCase(template: said, like: heardMatch)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Convenience for pipeline call sites: applies the user's learned
    /// corrections from the shared store.
    static func apply(_ text: String) -> String {
        apply(text, corrections: shared.all())
    }

    /// Mirrors the heard occurrence's case shape onto the replacement.
    private static func matchingCase(template: String, like sample: String) -> String {
        let letters = sample.filter { $0.isLetter }
        if !letters.isEmpty && letters == letters.uppercased() {
            return template.uppercased()
        }
        if let first = sample.first, first.isLetter, first.isUppercase {
            return template.prefix(1).uppercased() + template.dropFirst()
        }
        return template
    }

    // MARK: - Consumer 2: whisper initial prompt

    /// Builds the `--prompt` payload: the user's vocabulary as a compact,
    /// whisper-friendly string ("term: correction" pairs are noisy — the raw
    /// `said` phrases are what bias decoding). Capped by character budget so
    /// the prompt never grows unbounded (whisper caps at n_text_ctx/2 tokens;
    /// ~200 chars ≈ 50 tokens, well inside budget).
    static func initialPrompt(from corrections: [Correction], maxCharacters: Int = 200) -> String? {
        guard !corrections.isEmpty else { return nil }
        var parts: [String] = []
        var used = 0
        for c in corrections.sorted(by: { $0.createdAt > $1.createdAt }) {
            let piece = c.said
            if used + piece.count + 1 > maxCharacters { break }
            parts.append(piece)
            used += piece.count + 1
        }
        let prompt = parts.joined(separator: ", ")
        return prompt.isEmpty ? nil : prompt
    }

    /// Extracts the minimal (heard → said) pair from an original transcript
    /// and its user correction. Word-level first (clean phrase swaps); falls
    /// back to character-level for case/punctuation-only fixes ("tiago" →
    /// "Tiago" must still teach). Returns nil when there is nothing learnable
    /// (identical text, or a pure insertion/deletion with no replacement pair).
    /// Pure — tests need no disk.
    static func diffCorrection(original: String, corrected: String) -> (heard: String, said: String)? {
        let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty, !c.isEmpty, o != c else { return nil }
        // D033: an unrelated rewrite (field repurposed, different language,
        // pasted-over content) is not a vocabulary lesson. The watcher enforces
        // the same threshold on its own path; the manual path must too — this
        // exact gap poisoned a real store with an LLM system prompt.
        guard Paster.similarity(o, c) >= CorrectionWatcher.minSimilarity else { return nil }
        // D035: same alignment as the watcher's auto-learn path (word-level
        // first, character fallback) — the manual path must not re-introduce
        // the dead `telia.` → `telia` class of lesson the auto path just
        // learned to avoid.
        if let pair = CorrectionWatcher.wordLevelPair(e: o, t: c) { return pair }
        return CorrectionWatcher.charLevelPair(e: o, t: c)
    }

    /// Prompt from this store (pipeline call site in AppState).
    func initialPrompt() -> String? {
        Self.initialPrompt(from: all())
    }

    // MARK: - Persistence

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // must mirror the encoder, or saved corrections silently fail to load
        guard let data = try? Data(contentsOf: correctionsFile),
              let decoded = try? decoder.decode([Correction].self, from: data) else { return }
        cached = decoded
    }

    /// Called with `queue` held. Prepares the tree right before the write
    /// (V01-AC01: reads never create; only this write path does).
    private func persistLocked() {
        guard paths.prepareAppSupport() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: correctionsFile, options: .atomic)
    }
}
