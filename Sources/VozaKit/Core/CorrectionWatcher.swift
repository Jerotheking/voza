import AppKit
import ApplicationServices

/// Wispr-style auto-learn, local and scoped (owner decision 2026-09-08).
///
/// When Voza pastes, `Paster` records a `Session` (element + exact pre-paste
/// field + selection). This watcher polls ONLY that element — never the
/// system, never other fields — for a short window right after the paste,
/// waiting for the user to type their correction. Fast, close polling (0.8 s)
/// exists precisely because "looking much later" is what fails: we catch the
/// fix the moment the text stops moving, not by reconstructing history.
///
/// False-lesson guards: the field must stabilize across two consecutive
/// samples, differ from what Voza wrote, stay textually similar to it, and
/// differ in content (not just formatting). One learning per paste, then stop.
/// If Accessibility can't read the element, the session ends silently — the
/// ✏️ history button remains the manual path.
final class CorrectionWatcher {
    static let shared = CorrectionWatcher()

    // Tuning constants (asserted sane in the smoke suite).
    static let pollIntervalSeconds: TimeInterval = 0.8
    static let windowSeconds: TimeInterval = 20
    static let stabilitySamples = 2
    /// D036: pause is not proof — macOS accent menus (press-and-hold) and IME
    /// candidates freeze typing for seconds while composition is UNFINISHED
    /// (field evidence: "sinteli" was learned while the user was still
    /// composing "sinteliä" in the accent menu). After the stability gate,
    /// one extra read after this pause confirms the field truly settled.
    static let confirmationPauseSeconds: TimeInterval = 0.7
    static let minSimilarity = 0.55
    static let minSaidLength = 4
    static let maxLearnedChars = 400

    /// Injection seam (matt-tdd): everything the live loop needs to touch is
    /// a parameter with a production default — tests inject a fake reader, a
    /// fake sleep, a fixed clock and a QA sink, so integration tests run the
    /// REAL loop with zero AX calls, zero real sleeps, zero store writes.
    struct WatchConfig {
        let pollIntervalSeconds: TimeInterval
        let windowSeconds: TimeInterval
        let stabilitySamples: Int
        static let production = WatchConfig(pollIntervalSeconds: CorrectionWatcher.pollIntervalSeconds,
                                            windowSeconds: CorrectionWatcher.windowSeconds,
                                            stabilitySamples: CorrectionWatcher.stabilitySamples)
    }

    typealias FieldReader = (AXUIElement) -> String?

    /// Destination for learned pairs. Production: CorrectionStore. Tests: QASink.
    protocol LearningSink: AnyObject {
        @discardableResult
        func record(heard: String, said: String) -> Correction?
    }

    /// Test-only sink. Never touches the user's dictionary. Returns a real
    /// Correction value so the honest log path (record accepted → "learned")
    /// behaves exactly like production.
    final class QASink: LearningSink {
        private let lock = NSLock()
        private(set) var pairs: [(heard: String, said: String)] = []
        func record(heard: String, said: String) -> Correction? {
            lock.lock(); defer { lock.unlock() }
            pairs.append((heard, said))
            return Correction(id: UUID(), heard: heard, said: said, createdAt: Date())
        }
    }

    private let queue = DispatchQueue(label: "voza.correctionwatcher", qos: .utility)
    private let lock = NSLock()
    private var generation = 0

    var isWatching: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    private var active = false

    /// Begins watching the session's element. Cancels any previous watch
    /// (one session at a time — the newest paste wins).
    ///
    /// D041: ONE loop. `watch()` (live-baseline) and `watchLateBaseline()`
    /// previously duplicated the stability+confirmation machinery — D036's
    /// accent-menu fix had to be applied twice and the copies had already
    /// started drifting (one logged expiry, the other didn't). The two modes
    /// differ ONLY in how the expected field is obtained and whether a wake
    /// runs first; everything after that is the shared `observe()` core.
    func start(for session: Paster.Session) {
        lock.lock()
        generation += 1
        let gen = generation
        active = true
        lock.unlock()

        LearningLog.shared.event(.start(hasElement: session.element != nil))

        // No element → the paste landed in an app that doesn't expose text
        // semantics yet (Electron/Chromium). Wake its hidden AX support and
        // capture a LIVE baseline after the paste (D034, the Sintelia case).
        let mode: Mode = session.element == nil ? .lateBaseline : .liveBaseline
        queue.async { [weak self] in
            let continueCheck: (() -> Bool)? = self.map { watcher in
                { watcher.lock.lock(); defer { watcher.lock.unlock() }; return watcher.generation == gen && watcher.active }
            }
            _ = Self.watch(session: session, shouldContinue: continueCheck, mode: mode)
            guard let self else { return }
            self.lock.lock()
            if self.generation == gen { self.active = false }
            self.lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        generation += 1
        active = false
        lock.unlock()
    }

    /// How the watcher knows what the field looked like right after our
    /// paste — the ONLY difference between the two modes (D041).
    enum Mode {
        /// The pre-paste snapshot reconstructs the expected field exactly.
        case liveBaseline
        /// The app exposed no AX text at paste time: wake it, then adopt the
        /// first readable field that contains our paste as the baseline.
        case lateBaseline
    }

    /// The single watch loop, fully injectable for tests (D041). Phase 1
    /// (mode-specific): establish the baseline — reconstructed from the
    /// pre-paste snapshot, or captured live after waking a sleeping Chromium
    /// tree. Phase 2 (shared): poll the field until the window closes,
    /// learning at most one pair: the first stabilized, confirmed edit that
    /// passes every guard. Returns true when a pair was recorded into the
    /// sink.
    ///
    /// Injection seams: `readField` (live mode) reads the session element;
    /// `readFocused` (late mode) reads whatever is focused. Tests inject the
    /// one their mode needs; production defaults are built inside.
    @discardableResult
    static func watch(session: Paster.Session,
                      clock: Clock = SystemClock(),
                      readField: FieldReader? = nil,
                      readFocused: (() -> String?)? = nil,
                      sleep: ((TimeInterval) -> Void)? = nil,
                      shouldContinue: (() -> Bool)? = nil,
                      sink: LearningSink = CorrectionStore.shared,
                      config: WatchConfig = .production,
                      mode: Mode = .liveBaseline,
                      wake: (() -> Bool)? = nil) -> Bool {
        let doSleep = sleep ?? { Thread.sleep(forTimeInterval: $0) }

        // ── Phase 1: establish the expected field (mode-specific) ─────────
        let expected: String?
        switch mode {
        case .liveBaseline:
            expected = expectedField(after: session) // nil → corrupt pre-paste snapshot, nothing to verify against
        case .lateBaseline:
            let captured = captureLateBaseline(session: session,
                                               readFocused: readFocused,
                                               sleep: doSleep,
                                               shouldContinue: shouldContinue,
                                               config: config,
                                               wake: wake)
            if captured == nil { return false } // ax-never-woke already logged inside
            // P2-c (agy re-review 2026-09-22): a strict-prefix capture is an
            // AX truncation — the field mirrored only part of our paste
            // while the DOM settled. The user's edits happen on the FULL
            // paste, so phase 2 must diff against the pasted text, never
            // against the truncated fragment (a fragment pre-image yields
            // fragment lessons like heard="Sint").
            if let captured, captured != session.pastedText,
               session.pastedText.hasPrefix(captured) {
                expected = session.pastedText
            } else {
                expected = captured
            }
        }
        guard let expected else { return false }

        // ── Phase 2: shared observation (stability + confirmation + learn) ─
        let reader: () -> String?
        switch mode {
        case .liveBaseline:
            guard let element = session.element else { return false }
            // P1-4 (audit 2026-09-21): the messaging timeout is REAL AX —
            // tests inject a reader and must not touch it at all.
            if readField == nil { Paster.applyMessagingTimeout(element) }
            reader = { readField?(element) ?? Self.readField(element) }
        case .lateBaseline:
            reader = {
                if let readFocused { return readFocused() }
                guard let el = Paster.focusedElementPublic else { return nil }
                Paster.applyMessagingTimeout(el)
                return Self.readField(el)
            }
        }
        return observe(expected: expected, pasted: session.pastedText,
                       reader: reader, clock: clock, doSleep: doSleep,
                       shouldContinue: shouldContinue, sink: sink, config: config)
    }

    /// Phase 2 core, shared by both modes — the ONE place where stability,
    /// the D036 confirmation read, guard evaluation and learning happen.
    /// Polls `reader()` until the injected clock passes the window deadline,
    /// `shouldContinue` turns false, or one lesson is recorded.
    @discardableResult
    private static func observe(expected: String,
                                pasted: String,
                                reader: () -> String?,
                                clock: Clock,
                                doSleep: (TimeInterval) -> Void,
                                shouldContinue: (() -> Bool)?,
                                sink: LearningSink,
                                config: WatchConfig) -> Bool {
        var lastValue: String?
        var stableCount = 0
        let deadline = clock.now.addingTimeInterval(config.windowSeconds)

        while clock.now < deadline {
            if let shouldContinue, !shouldContinue() { return false }
            doSleep(config.pollIntervalSeconds)

            guard let current = reader() else {
                // Element unreadable right now (app swallowed it, AX hiccup):
                // reset stability and keep trying until the window closes.
                lastValue = nil
                stableCount = 0
                continue
            }
            let unchanged = current == expected
                || (current as NSString).contains(pasted) // our text still intact (chat-style larger fields)
            if unchanged {
                stableCount = 0 // user undid back to our text, or app restored it
                lastValue = current
                continue
            }
            if current == lastValue {
                stableCount += 1
            } else {
                stableCount = 1
            }
            lastValue = current

            // Stable for N consecutive samples ≈ typing paused. D036: a pause
            // is not proof — the confirm read (extra read after a pause)
            // catches resumed typing, reader hiccups and not-yet-valid
            // fragments (accent menu, IME). Everything except a confirmed,
            // valid, stable edit re-arms stability and keeps watching: only
            // the window expiry ends a session, never a frozen half-typed value.
            if stableCount >= config.stabilitySamples {
                doSleep(Self.confirmationPauseSeconds)
                let confirmed = reader()
                if let confirmed, confirmed == current,
                   let pair = extractPair(pasted: pasted, typed: confirmed, expected: expected) {
                    let stored = sink.record(heard: pair.heard, said: pair.said)
                    // Log honesty (D034): "learned" only when the sink actually
                    // accepted (record can refuse: caps, heard == said). Tests
                    // (QASink) never fake a "learned" line in the user's bitácora.
                    LearningLog.shared.event(stored != nil
                        ? .learned(heard: pair.heard, said: pair.said)
                        : .expired)
                    return stored != nil // exactly one learning attempt per paste
                }
                if let confirmed {
                    stableCount = 1
                    lastValue = confirmed
                } else {
                    stableCount = 0
                    lastValue = nil
                }
                continue
            }
        }
        LearningLog.shared.event(.expired)
        return false
    }

    // MARK: - Pure decision logic (smoke-tested; no AX, no clock, no disk)

    /// The field state the watcher EXPECTS right after our paste, rebuilt
    /// exactly from the pre-paste snapshot. Never guessed: reconstruction
    /// means every "different" observation is a real user edit. Honors the
    /// selection LENGTH: a paste over a selection REPLACES it (caught by the
    /// adversarial smoke — the insertion-only formula double-counted the
    /// replaced text and would have poisoned every diff in that case).
    static func expectedField(after session: Paster.Session) -> String? {
        let ns = session.fieldBefore as NSString
        let loc = session.selectedRange.location
        let len = session.selectedRange.length
        guard loc >= 0, len >= 0, loc + len <= ns.length else { return nil }
        let before = ns.substring(to: loc)
        let after = ns.substring(from: loc + len)
        return before + session.pastedText + after
    }

    /// Extracts the learned pair from what the user typed, or nil when the
    /// observation must NOT become a lesson (guards documented inline).
    ///
    /// Core algorithm: a three-part diff (common prefix / changed middle /
    /// common suffix) between the expected field and the typed field isolates
    /// EXACTLY what the user changed — never the whole field. This keeps
    /// lessons clean when Voza pasted into a field with existing text:
    /// "Hola, " + paste("esto es una prueva") fixed to "…una prueba" yields
    /// ("prueva" → "prueba"), not the whole sentence.
    static func extractPair(pasted: String, typed: String, expected: String) -> (heard: String, said: String)? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= minSaidLength else { return nil }                    // trivial edit / UI chrome
        guard t != e else { return nil }                                       // nothing changed
        // Formatting-only change (case/whitespace): the app's autocorrect, not the user's vocabulary.
        // D035: same LETTERS but a different token split ("sin telia" →
        // "sintelia") is a real merge/split lesson and must pass; a pure
        // case/punctuation change still dies here (the whole-word replacer
        // mirrors case anyway, so such a lesson could never fire).
        let canon = { (s: String) -> String in s.lowercased().filter { !$0.isWhitespace } }
        if canon(t) == canon(e) {
            let et = e.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let tt = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard et != tt else { return nil }
        }
        // Unrelated replacement (URL pasted over, field cleared and rewritten): too dangerous to learn.
        guard Paster.similarity(e, t) >= minSimilarity else { return nil }

        // D035: two diff granularities, tried in order. Both yield a raw
        // (heard, said) fragment; `valid` then applies the shared acceptance
        // guards (lengths, non-identity, containment in OUR paste).
        func valid(_ pair: (heard: String, said: String)?) -> (heard: String, said: String)? {
            guard let (h, fix) = pair else { return nil }
            // D051 + D055 (pstack blast-radius): require at least one letter on both sides
            // so pure number edits ("10" -> "45") never poison the dictionary, while 2-3 char
            // acronyms and alphanumeric tokens ("ia" -> "AI", "v2" -> "v3", "s3" -> "S3") pass.
            guard h.contains(where: \.isLetter), fix.contains(where: \.isLetter) else { return nil }
            let effectiveMinSaid = fix.contains(where: { $0.isUppercase || $0.isNumber }) ? 2 : minSaidLength
            guard h.count >= 2, fix.count >= effectiveMinSaid, h.count <= maxLearnedChars,
                  fix.count <= maxLearnedChars else { return nil }
            guard h != fix else { return nil } // nothing left to learn
            // Pure-case single-token pair ("tiago" → "Tiago"): dead weight —
            // the replacer's matchingCase already mirrors case shape, so such
            // a lesson can never change an output. Merge/split lessons are
            // canon-equal too but span a space, and stay welcome.
            let canonPair = { (x: String) -> String in x.lowercased() }
            if canonPair(h) == canonPair(fix), !h.contains(" "), !fix.contains(" ") { return nil }
            // The lesson must be about OUR text: the heard side must appear
            // inside what Voza pasted. Edits to the user's surrounding
            // context (their own words before/after the paste) are never
            // attributed to the model.
            guard pasted.range(of: h, options: .caseInsensitive) != nil else { return nil }
            return (h, fix)
        }
        if let pair = valid(Self.wordLevelPair(e: e, t: t)) { return pair }
        return valid(Self.charLevelPair(e: e, t: t))
    }

    /// D035 — word-level alignment, tried first because it handles the two
    /// topologies the character diff corrupts:
    ///
    /// 1. End-of-sentence fixes: correcting "…? Sin telia." → "…? Sintelia"
    ///    diffs at character level as "telia." → "telia" — the sentence-final
    ///    period gets welded into the fragment (real bug, shipped: the store
    ///    learned the dead pair `telia.` → `telia`, unusable by the whole-word
    ///    replacer and polluting the whisper prompt).
    /// 2. Merges and splits across the space: "Sin telia" → "Sintelia" (and
    ///    the reverse) — the change spans the boundary a character diff
    ///    can't express as one replayable replacement.
    ///
    /// Tokens carry their attached punctuation so prefix/suffix anchoring is
    /// honest ("funcionar?" ≠ "funcionar"); the changed middle is then
    /// edge-trimmed to letters. Whitespace-only differences die in the
    /// caller's canonical guard before we get here.
    static func wordLevelPair(e: String, t: String) -> (heard: String, said: String)? {
        let ew = e.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let tw = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var prefix = 0
        while prefix < ew.count && prefix < tw.count && ew[prefix] == tw[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < ew.count - prefix && suffix < tw.count - prefix
                && ew[ew.count - 1 - suffix] == tw[tw.count - 1 - suffix] { suffix += 1 }
        let heardMid = ew[prefix..<(ew.count - suffix)].joined(separator: " ")
        let saidMid = tw[prefix..<(tw.count - suffix)].joined(separator: " ")
        guard !heardMid.isEmpty, !saidMid.isEmpty else { return nil }
        let h = trimmedToWordBoundaries(heardMid)
        let fix = trimmedToWordBoundaries(saidMid)
        guard !h.isEmpty, !fix.isEmpty, h != fix else { return nil }
        return (h, fix)
    }

    /// Character-level diff with mid-word expansion — the fallback, precise
    /// when the change lives inside one word ("prueva" → "prueba" diffs as
    /// "v" → "b", which word alignment would teach as the whole words).
    static func charLevelPair(e: String, t: String) -> (heard: String, said: String)? {
        let es = Array(e), ts = Array(t)
        var p = 0
        let minLen = min(es.count, ts.count)
        while p < minLen && es[p] == ts[p] { p += 1 }
        var s = 0
        while s < minLen - p && es[es.count - 1 - s] == ts[ts.count - 1 - s] { s += 1 }
        // Pure insertion/deletion (one side empty): real, but not a replayable
        // replacement — skipped in v1 (the ✏️ history button covers those).
        guard p < es.count - s, p < ts.count - s else { return nil }

        let esEnd = es.count - s
        let tsEnd = ts.count - s
        let heardMid = String(es[p..<esEnd])
        let saidMid = String(ts[p..<tsEnd])
        var h = trimmedToWordBoundaries(heardMid)
        var fix = trimmedToWordBoundaries(saidMid)
        guard !h.isEmpty, !fix.isEmpty else { return nil }

        // Mid-word cut (user paused inside a word): expand BOTH sides to
        // their containing words, otherwise we would teach a garbage
        // single-letter pair that whole-word replace can never fire safely.
        // Multi-word realignments mid-cut are refused.
        let startsMidWord = p > 0 && es[p - 1].isLetter && es[p].isLetter
        let endsMidWord = esEnd > p && es[esEnd - 1].isLetter && esEnd < es.count && es[esEnd].isLetter
        if startsMidWord || endsMidWord {
            guard !heardMid.contains(" ") && !saidMid.contains(" ") else { return nil }
            var wS = p, wE = esEnd, tS = p, tE = tsEnd
            while wS > 0 && es[wS - 1].isLetter { wS -= 1 }
            while wE < es.count && es[wE].isLetter { wE += 1 }
            while tS > 0 && ts[tS - 1].isLetter { tS -= 1 }
            while tE < ts.count && ts[tE].isLetter { tE += 1 }
            h = String(es[wS..<wE])
            fix = String(ts[tS..<tE])
            guard h != fix else { return nil }
        }
        guard !h.isEmpty, !fix.isEmpty else { return nil }
        return (h, fix)
    }

    /// D035: strips edge non-letter characters from a diff middle (sentence
    /// punctuation welded to the fragment — "telia." → "telia"). Inner
    /// characters are never touched, so abbreviations like "Dr." keep their
    /// period when the diff cut inside a word (mid-word expansion path).
    static func trimmedToWordBoundaries(_ s: String) -> String {
        var t = s
        while let f = t.first, !f.isLetter && !f.isNumber, t.count > 1 { t.removeFirst() }
        while let l = t.last, !l.isLetter && !l.isNumber, t.count > 1 { t.removeLast() }
        return t
    }

    /// Reads kAXValueAttribute; nil when the element is gone or unreadable.
    static func readField(_ element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return value
    }

    // MARK: - Chromium wake (D040: attribute-only, NO VoiceOver, ever)

    /// Wakes a Chromium/Electron app's web-content accessibility tree by
    /// setting `AXManualAccessibility` on every **AXWebArea**, found by
    /// walking the app's OWN tree (windows/buttons — readable even when web
    /// content is dark). This is Chromium's documented manual-override path,
    /// implemented by its renderer; the field experiment on Freebuff
    /// (18 Sep 2026) woke the web tree in ~1 s with the focused element
    /// readable — NO VoiceOver, no keystrokes, no audio, no visible blip.
    /// The previous VoiceOver-toggle approach is deleted: it could speak out
    /// loud (D039) and flicker UI; the owner required it to never happen.
    @discardableResult
    static func wakeAppTree(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2.0)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement] else { return false }
        var stuck = false
        var budget = 400
        func walk(_ el: AXUIElement, depth: Int) {
            guard budget > 0, depth < 14 else { return }
            budget -= 1
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else { return }
            if role == "AXWebArea" {
                AXUIElementSetMessagingTimeout(el, 2.0)
                let r = AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                if r == .success { stuck = true }
                return // webAreas are the wake targets; don't walk their content
            }
            var kidsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
                  let kids = kidsRef as? [AXUIElement] else { return }
            for k in kids { walk(k, depth: depth + 1) }
        }
        for w in wins { walk(w, depth: 0) }
        return stuck
    }

    // MARK: - Late-baseline capture (Electron/Chromium, D034/D041)

    /// Phase 1 of late-baseline mode (D041): wake a sleeping Chromium AX tree
    /// and adopt the first readable focused field that contains our paste as
    /// the baseline. Observation afterwards happens in the SHARED core
    /// (`observe`) — the old duplicate loop is gone (D036 used to be patched
    /// in two places; that can never happen again).
    /// Electron apps (Slack, VS Code, Discord, Chromium browsers…) gate their
    /// web-content accessibility tree; we wake it with the attribute-only
    /// `wakeAppTree` (D040 — never VoiceOver). The tree takes a moment to
    /// build, so we poll the focused element for up to ~5 s. Difference rules
    /// are inherited from the shared core: the baseline IS what we pasted;
    /// if the app exposes a larger field, the paste is contained within it.
    /// Returns nil (and logs `ax-never-woke`) when the field never became
    /// readable — a distinct failure mode from "woke but no approved edit".
    static func captureLateBaseline(session: Paster.Session,
                                    readFocused: (() -> String?)?,
                                    sleep: (TimeInterval) -> Void,
                                    shouldContinue: (() -> Bool)?,
                                    config: WatchConfig,
                                    wake: (() -> Bool)?) -> String? {
        let reader: () -> String? = {
            if let readFocused { return readFocused() }
            guard let el = Paster.focusedElementPublic else { return nil }
            Paster.applyMessagingTimeout(el)
            return readField(el)
        }
        // D040: the wake side effect is a seam. Tests MUST inject a fake —
        // the default (below) walks real AX trees. It is attribute-only: it
        // can NEVER launch VoiceOver, post keystrokes or touch audio. The
        // default resolves the pasted-into app by PID (element first, focus
        // as fallback) so the wake targets the right app even if focus moves
        // mid-session; with an injected wake, NO real AX runs — hermetic.
        let defaultWake: () -> Bool = {
            var pid = pid_t(0)
            if let el = session.element { AXUIElementGetPid(el, &pid) }
            if pid <= 0, let focused = Paster.focusedElementPublic {
                AXUIElementGetPid(focused, &pid)
            }
            if pid > 0 { _ = Self.wakeAppTree(pid: pid) }
            return Paster.forceAccessibilityOnFocusedApp()
        }
        let wakeFn = wake ?? defaultWake
        let pollSeconds = config.pollIntervalSeconds
        let axWakeSeconds = 5.0

        // Wake and wait until the field reflects our paste — re-waking on
        // EVERY poll, because Chromium builds its tree lazily and the first
        // poke often doesn't stick (D034 field evidence: Freebuff needed
        // repeats). Field experiment (18 Sep 2026): Freebuff's web tree woke
        // in ~1 s with the focused element readable.
        let pasted = session.pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var waited = 0.0
        var wakeAccepted = 0
        var wakeUnsupported = 0
        while waited < axWakeSeconds {
            if let shouldContinue, !shouldContinue() { return nil }
            if wakeFn() { wakeAccepted += 1 } else { wakeUnsupported += 1 }
            sleep(pollSeconds)
            waited += pollSeconds
            // P0-3 (audit 2026-09-21): `pasted.contains("")` is ALWAYS true in
            // Swift — an empty or whitespace-only reading (field not yet
            // propagated in Chromium's DOM, or genuinely empty field) matched
            // instantly and captured "" as the baseline, wrecking phase-2
            // lesson extraction in exactly the Electron apps this mode
            // targets. A valid baseline must be non-empty AND related to the
            // paste (our text intact, our text inside a larger field, or an
            // AX truncation of it — a PREFIX of our paste, since some fields
            // only mirror the leading part while the DOM settles).
            if let current = reader() {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty,
                   current.contains(pasted) || pasted.hasPrefix(trimmed) {
                    return current
                }
            }
        }
        // accepted = the app ACKNOWLEDGED the override (tree just never
        // built); unsupported = the app rejected the attribute outright
        // (its Electron build doesn't implement the handler at all).
        LearningLog.shared.event(.axNeverWoke(accepted: wakeAccepted, unsupported: wakeUnsupported))
        return nil
    }
}

/// Production sink: learned pairs go to the user's dictionary. Declared here
/// so the injection seam and its default live together; the signature was
/// already protocol-shaped (`record(heard:said:) -> Correction?`).
extension CorrectionStore: CorrectionWatcher.LearningSink {}
