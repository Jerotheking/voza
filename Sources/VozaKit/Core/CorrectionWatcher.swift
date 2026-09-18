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
    func start(for session: Paster.Session) {
        lock.lock()
        generation += 1
        let gen = generation
        active = true
        lock.unlock()

        LearningLog.shared.event(.start(hasElement: session.element != nil))

        // No element → the paste landed in an app that doesn't expose text
        // semantics yet (Electron/Chromium). Force its hidden AX support and
        // capture a LIVE baseline after the paste (D034, the Sintelia case).
        guard session.element != nil else {
            queue.async { [weak self] in
                let continueCheck: (() -> Bool)? = self.map { watcher in
                    { watcher.lock.lock(); defer { watcher.lock.unlock() }; return watcher.generation == gen && watcher.active }
                }
                _ = Self.watchLateBaseline(session: session, shouldContinue: continueCheck)
                guard let self else { return }
                self.lock.lock()
                if self.generation == gen { self.active = false }
                self.lock.unlock()
            }
            return
        }

        queue.async { [weak self] in
            let continueCheck: (() -> Bool)? = self.map { watcher in
                { watcher.lock.lock(); defer { watcher.lock.unlock() }; return watcher.generation == gen && watcher.active }
            }
            _ = Self.watch(session: session, shouldContinue: continueCheck)
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

    /// The live watch loop, fully injectable for tests. Reads the session's
    /// element every `config.pollIntervalSeconds` until `config.windowSeconds`
    /// elapse (on the injected clock) or `shouldContinue` turns false. Learns
    /// at most one pair: the first stabilized edit that passes every guard.
    /// Returns true when a pair was recorded into the sink.
    @discardableResult
    static func watch(session: Paster.Session,
                      clock: Clock = SystemClock(),
                      readField: FieldReader? = nil,
                      sleep: ((TimeInterval) -> Void)? = nil,
                      shouldContinue: (() -> Bool)? = nil,
                      sink: LearningSink = CorrectionStore.shared,
                      config: WatchConfig = .production) -> Bool {
        guard let element = session.element else { return false }
        guard let expected = expectedField(after: session) else { return false } // corrupt pre-paste snapshot → nothing to verify against
        let reader = readField ?? { el in
            Paster.applyMessagingTimeout(el)
            return Self.readField(el)
        }
        let doSleep = sleep ?? { Thread.sleep(forTimeInterval: $0) }
        var lastValue: String?
        var stableCount = 0
        let deadline = clock.now.addingTimeInterval(config.windowSeconds)

        while clock.now < deadline {
            if let shouldContinue, !shouldContinue() { return false }
            doSleep(config.pollIntervalSeconds)

            guard let current = reader(element) else {
                // Element unreadable right now (app swallowed it, AX hiccup):
                // reset stability and keep trying until the window closes.
                lastValue = nil
                stableCount = 0
                continue
            }
            if current == expected {
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
            // fragments. Everything except a confirmed, valid, stable edit
            // re-arms stability and keeps watching: only the window expiry
            // ends a session, never a frozen half-typed value.
            if stableCount >= config.stabilitySamples {
                doSleep(Self.confirmationPauseSeconds)
                let confirmed = reader(element)
                if let confirmed, confirmed == current,
                   let pair = extractPair(pasted: session.pastedText, typed: confirmed, expected: expected) {
                    let stored = sink.record(heard: pair.heard, said: pair.said)
                    // Same log honesty as the late-baseline path: tests (QASink)
                    // never fake a "learned" line in the user's bitácora.
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
            guard h.count >= 2, fix.count >= minSaidLength, h.count <= maxLearnedChars,
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
        while let f = t.first, !f.isLetter, t.count > 1 { t.removeFirst() }
        while let l = t.last, !l.isLetter, t.count > 1 { t.removeLast() }
        return t
    }

    /// Reads kAXValueAttribute; nil when the element is gone or unreadable.
    static func readField(_ element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return value
    }

    // MARK: - VoiceOver wake (the Chromium canary)

    /// Chromium/Electron enables its accessibility tree when it detects a
    /// screen reader; the manual AXManualAccessibility attribute is not
    /// implemented by every Electron build (D034 field evidence: Freebuff
    /// answers `attributeUnsupported`). The reliable wake is toggling
    /// VoiceOver on→off: Chromium sees VO start and keeps AX enabled after it
    /// stops. Voza sends ⌘F5 twice (VO on, then off) — net effect is a short
    /// system blip, no speech content, and the tree stays awake for the
    /// session. Requires Input Monitoring (same permission as the hotkey).
    /// Returns false when the keystrokes could not be posted.
    @discardableResult
    static func wakeAccessibilityViaVoiceOverToggle() -> Bool {
        func tapF5() -> Bool {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: false) else { return false }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            usleep(60_000)
            up.post(tap: .cghidEventTap)
            return true
        }
        guard tapF5() else { return false }
        usleep(900_000) // let Chromium notice VO started
        guard tapF5() else { return false }
        LearningLog.shared.event(.voWake)
        return true
    }

    // MARK: - Late-baseline mode (Electron/Chromium, D034)

    /// Watches a paste whose target app exposed no AX text at capture time.
    /// Electron apps (Slack, VS Code, Discord, Chromium browsers…) gate their
    /// accessibility tree behind VoiceOver detection — or the manual
    /// `AXManualAccessibility` override, which is exactly what we set here
    /// (same trick VO uses). The tree takes a moment to build, so we poll the
    /// focused element for up to ~5 s until kAXValue reads our pasted text,
    /// then diff the LIVE field against that baseline with the SAME guards as
    /// the normal path. Difference rules: the baseline starts as `pasted` (it
    /// IS what we pasted); if the app exposes a larger field, the paste is
    /// contained within it — containment counts as "unchanged so far".
    static func watchLateBaseline(session: Paster.Session,
                                  clock: Clock = SystemClock(),
                                  readFocused: (() -> String?)? = nil,
                                  sleep: ((TimeInterval) -> Void)? = nil,
                                  shouldContinue: (() -> Bool)? = nil,
                                  sink: LearningSink = CorrectionStore.shared,
                                  config: WatchConfig = .production,
                                  force: (() -> Bool)? = nil,
                                  voWake: (() -> Bool)? = nil) -> Bool {
        let doSleep = sleep ?? { Thread.sleep(forTimeInterval: $0) }
        let reader = readFocused ?? {
            guard let el = Paster.focusedElementPublic else { return nil }
            Paster.applyMessagingTimeout(el)
            return readField(el)
        }
        // D037: the escalation side effects are seams. Tests MUST inject
        // fakes — the defaults touch real AX and post real ⌘F5 events.
        let forceFn = force ?? { Paster.forceAccessibilityOnFocusedApp() }
        let wakeFn = voWake ?? { Self.wakeAccessibilityViaVoiceOverToggle() }
        let pollSeconds = config.pollIntervalSeconds
        let settleSeconds = 1.0
        let axWakeSeconds = 5.0

        // 1)+2) Wake the app's AX tree (manual overrides, the VO trick) and
        // wait until the field reflects our paste — RE-FORCING on every poll,
        // because Chromium builds its tree lazily and the first poke often
        // doesn't stick (D034 field evidence: Freebuff needed repeats).
        let pasted = session.pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var baseline: String?
        var waited = 0.0
        var forcedAccepted = 0
        var forcedUnsupported = 0
        var wakeBudget = axWakeSeconds
        var voTried = false
        while waited < wakeBudget {
            if let shouldContinue, !shouldContinue() { return false }
            if forceFn() { forcedAccepted += 1 } else { forcedUnsupported += 1 }
            // D037: escalate INSIDE the wait window. After 4 failed wake
            // attempts (~3 s at production cadence) fire the VoiceOver toggle
            // once — VO detection is compiled into every Chromium renderer,
            // unlike the manual-override attribute Freebuff rejects — and
            // EXTEND the budget so there is time left to observe the tree it
            // builds. The previous shape (toggle after give-up, one
            // confirmation read) could not even reach the watch phase when
            // that single read came back empty (00:1x field log).
            if !voTried, (forcedAccepted + forcedUnsupported) >= 4 {
                voTried = true
                if wakeFn() { wakeBudget += 3.0 } // tree construction after VO detection
            }
            doSleep(pollSeconds)
            waited += pollSeconds
            if let current = reader(), current.contains(pasted) || pasted.contains(current.trimmingCharacters(in: .whitespacesAndNewlines)) {
                baseline = current
                break
            }
        }
        if baseline == nil {
            // Distinguish "AX never woke" (fixable later) from "woke but the
            // user made no approved edit" — different remediation paths.
            // accepted = the app ACKNOWLEDGED the override (tree just never
            // built); unsupported = the app rejected the attribute outright
            // (its Electron build doesn't implement the handler at all).
            LearningLog.shared.event(.axNeverWoke(accepted: forcedAccepted, unsupported: forcedUnsupported))
        }
        guard let baseline else { return false }

        // 3) Let the user's correction land (settle) and diff against baseline.
        doSleep(settleSeconds)
        let deadline = clock.now.addingTimeInterval(config.windowSeconds)
        var lastValue: String?
        var stableCount = 0
        while clock.now < deadline {
            if let shouldContinue, !shouldContinue() { return false }
            doSleep(pollSeconds)
            guard let current = reader() else { continue }
            let unchanged = (current == baseline)
                || (current as NSString).contains(pasted) // our text still intact
            if unchanged {
                stableCount = 0
                lastValue = current
                continue
            }
            if current == lastValue {
                stableCount += 1
            } else {
                stableCount = 1
            }
            lastValue = current
            if stableCount >= config.stabilitySamples {
                // D036 confirmation pause (see watch()): a stable-looking field
                // may be frozen mid-composition (accent menu / IME). Re-read
                // after a pause; only a still-identical field whose edit is a
                // valid lesson may learn — everything else re-arms and the
                // window expiry remains the only failure exit.
                doSleep(Self.confirmationPauseSeconds)
                let confirmed = reader()
                if let confirmed, confirmed == current,
                   let pair = extractPair(pasted: session.pastedText, typed: confirmed, expected: baseline) {
                    // Log HONESTY (D034): "learned" only when the sink actually
                    // accepted (record can refuse: caps, heard == said). The
                    // QASink returns nil — tests must never write "learned"
                    // lines into the user's real bitácora.
                    let stored = sink.record(heard: pair.heard, said: pair.said)
                    LearningLog.shared.event(stored != nil
                        ? .learned(heard: pair.heard, said: pair.said)
                        : .expired)
                    return stored != nil
                }
                if let confirmed {
                    stableCount = 1
                    lastValue = confirmed
                } else {
                    stableCount = 0
                    lastValue = nil
                }
            }
        }
        LearningLog.shared.event(.expired)
        return false
    }
}

/// Production sink: learned pairs go to the user's dictionary. Declared here
/// so the injection seam and its default live together; the signature was
/// already protocol-shaped (`record(heard:said:) -> Correction?`).
extension CorrectionStore: CorrectionWatcher.LearningSink {}
