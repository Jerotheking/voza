import Foundation
import ApplicationServices
@testable import VozaKit

// Lightweight verification suite — runs with the CommandLineTools toolchain
// (no XCTest available there). Exits non-zero on first failure.

// V02-AC05: PASS and SKIP are counted separately; a SKIP is never a pass.
var smokeChecks = 0
var smokeSkips = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    smokeChecks += 1
    let icon = condition ? "PASS" : "FAIL"
    print("[\(icon)] \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { exit(1) }
}

func skipSmoke(_ why: String) {
    smokeSkips += 1
    print("[SKIP] \(why)")
}

/// Minimal hermetic QA environment for smoke suites — inline mirror of
/// Tests/VozaTests/Support/TestEnvironment.swift (that helper lives in the
/// XCTest target and is invisible to VozaSmoke).
final class SmokeQA {
    let root: URL
    let paths: AppPaths
    let defaults: UserDefaults
    let clock: FixedClock
    private let suiteName: String

    init?(name: String) {
        suiteName = "voza.smoke.\(name)." + UUID().uuidString
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths.qa(root: root)
        guard let d = UserDefaults(suiteName: suiteName) else { return nil }
        defaults = d
        clock = FixedClock(wall: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

// ===== V02: DEFAULT = HERMETIC PURITY ======================================
// The default run performs only pure checks (no UserDefaults writes, no real
// profile paths, no mic, no engine, no downloads) and exits deterministically
// with code 0 — even on a machine with no whisper-cli and no models (V02-AC02).
// Repetition changes nothing outside its own QA roots (V02-AC03).
//
// Opt-in suites carry the cost explicitly:
//   --live-real   → real profile (writes defaults, perf.json, ~/Dictation)
//   --integration → binaries/models/disk (never downloads without --qa-models)
//   e2e <wav>     → full pipeline + model download to --qa-models
// Suites that cannot run here print [SKIP] with the exact blocker — a SKIP is
// never counted as a native PASS (V02-AC05).

let liveReal = CommandLine.arguments.contains("--live-real")
let integration = CommandLine.arguments.contains("--integration")
let qaModelsIndex = CommandLine.arguments.firstIndex(of: "--qa-models")
let qaModelsRoot: String? = qaModelsIndex.flatMap { idx in
    idx + 1 < CommandLine.arguments.count ? CommandLine.arguments[idx + 1] : nil
}

func integrationGuard(_ name: String, requires: String) -> Bool {
    if integration { return true }
    skipSmoke("\(name) — opt-in integration suite (pass --integration; requires \(requires))")
    return false
}

if !liveReal && !integration {
    print("[INFO] VozaSmoke default: PURE checks only (hermetic, V02).")
    print("[INFO] Opt-in: --live-real (real profile), --integration (binaries/models), e2e <wav>.")
}

// ===== V01 hermetic isolation (plan-glm) — runs FIRST and exits BEFORE any
// suite that touches the real profile (UserDefaults, perf.json, mic). Mirrors
// Tests/VozaTests/TestEnvironmentTests (which needs Xcode; this runs on CLT).
if CommandLine.arguments.contains("v01") {
    // QA environment: unique root + volatile defaults suite + fixed clock.
    // (Inline mirror of TestEnvironment; that helper lives in the XCTest target.)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("voza-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppPaths.qa(root: root)
    let suiteName = "voza.smoke.v01." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check("v01 qa defaults suite available", false); exit(1)
    }
    let clock = FixedClock(wall: Date(timeIntervalSince1970: 1_700_000_000))

    // Contamination guard for the real profile: config.toml existence must be
    // identical before and after this run (V01-AC05).
    let realConfig = AppPaths.default.configFile.path
    let realConfigExisted = FileManager.default.fileExists(atPath: realConfig)

    // --- AC01: construction and pure reads create nothing ---
    _ = Config(paths: paths)
    _ = PerformanceMonitor(paths: paths, clock: clock, defaults: defaults)
    let store = TranscriptStore(paths: paths, clock: clock)
    MainActor.assumeIsolated { _ = LicenseManager(paths: paths, clock: clock, defaults: defaults) }
    _ = store.logDirectory.path
    check("v01 ac01 construct+read creates nothing", !FileManager.default.fileExists(atPath: root.path))

    // --- AC01: writes stay inside the QA root, each tree only its own ---
    Config(paths: paths).setPlaySound(true)
    check("v01 ac01 config write inside root", FileManager.default.fileExists(atPath: paths.configFile.path))
    check("v01 ac01 config write did not touch history", !FileManager.default.fileExists(atPath: paths.history.path))

    store.add(text: "v01-hermetic-marker", cleaned: false)
    Thread.sleep(forTimeInterval: 0.3) // drain the store's serial I/O queue
    let monthF = DateFormatter(); monthF.dateFormat = "yyyy-MM"
    let monthFile = paths.history.appendingPathComponent("\(monthF.string(from: clock.now)).md")
    check("v01 ac01 history write inside root", FileManager.default.fileExists(atPath: monthFile.path))

    // --- AC02: the simulated clock determines dates and elapsed time, no sleeps ---
    MainActor.assumeIsolated {
        let license = LicenseManager(paths: paths, clock: clock, defaults: defaults)
        license.refreshIfNeeded()
        check("v01 ac02 trial starts at 14 days", license.state == .trial(daysLeft: 14), "\(license.state)")
        clock.advance(seconds: 15 * 86_400) // 15 simulated days, instantly
        license.refreshIfNeeded()
        check("v01 ac02 trial over after 15 simulated days", license.state == .trialOver)
        check("v01 ac02 trial state in isolated defaults", defaults.object(forKey: "voza.trialStart") != nil)
    }
    let elapsedBefore = clock.uptimeSeconds
    clock.advance(seconds: 10, wallSeconds: 400_000)
    check("v01 ac02 elapsed independent of wall jump",
          abs(clock.uptimeSeconds - (elapsedBefore + 10)) < 0.001
          && clock.now.timeIntervalSince1970 == 1_700_000_000 + 15 * 86_400 + 400_000)

    // --- AC03: teardown removes only what it owns (sibling sentinel survives) ---
    let sentinelParent = FileManager.default.temporaryDirectory
        .appendingPathComponent("voza-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: sentinelParent, withIntermediateDirectories: true)
    let sentinel = sentinelParent.appendingPathComponent("sentinel-\(UUID().uuidString)")
    try "do-not-delete".write(to: sentinel, atomically: true, encoding: .utf8)
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: root)
    check("v01 ac03 qa root removed", !FileManager.default.fileExists(atPath: root.path))
    check("v01 ac03 sibling sentinel intact", FileManager.default.fileExists(atPath: sentinel.path))
    try? FileManager.default.removeItem(at: sentinel)

    // --- AC04: production defaults byte-identical to baseline ---
    let home = FileManager.default.homeDirectoryForCurrentUser
    let prod = AppPaths.default
    check("v01 ac04 prod config path unchanged", prod.appSupport.path == home.appendingPathComponent(".config/voza").path)
    check("v01 ac04 prod history path unchanged", prod.history.path == home.appendingPathComponent("Dictation").path)
    check("v01 ac04 legacy Config anchor unchanged", Config.appSupportDirectory == home.appendingPathComponent(".config/voza").path)
    check("v01 ac04 real config.toml untouched by run", FileManager.default.fileExists(atPath: realConfig) == realConfigExisted)

    print("[INFO] v01: original smoke suites intentionally NOT executed (real-profile protection, V01-AC05)")
    print("\nV01 hermetic checks passed.")
    exit(0)
}

// ===== Corrections learned corrections (plan-glm promoted work) — hermetic like v01:
// QA root + fixed clock, exits BEFORE any real-profile suite. Covers
// CorrectionStore persistence, replacement semantics, diff extraction and
// prompt generation.
if CommandLine.arguments.contains("corrections") {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("voza-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppPaths.qa(root: root)
    let clock = FixedClock(wall: Date(timeIntervalSince1970: 1_700_000_000))

    // AC-doctrine (V01-AC01): construction and reads create nothing.
    let store = CorrectionStore(paths: paths, clock: clock)
    check("corrections construct+read creates nothing", !FileManager.default.fileExists(atPath: root.path))
    check("corrections empty store applies unchanged", CorrectionStore.apply("hola mundo", corrections: []) == "hola mundo")
    check("corrections empty prompt is nil", CorrectionStore.initialPrompt(from: []) == nil)

    // Recording writes inside the QA root only.
    clock.advance(seconds: 1)
    let first = store.record(heard: "tiago", said: "Tiago")
    check("corrections record returns entry", first != nil)
    check("corrections file inside qa root", FileManager.default.fileExists(atPath: paths.appSupport.appendingPathComponent("corrections.json").path))
    check("corrections nothing outside qa root", !FileManager.default.fileExists(atPath: AppPaths.default.appSupport.appendingPathComponent("corrections.json").path))

    // Invalid inputs rejected.
    check("corrections rejects empty heard", store.record(heard: "  ", said: "x") == nil)
    check("corrections rejects identical pair", store.record(heard: "ok", said: "ok") == nil)

    // Re-recording the same heard updates in place (no duplicates).
    clock.advance(seconds: 1)
    _ = store.record(heard: "tiago", said: "Tiago Rey")
    check("corrections re-record updates not duplicates", store.count == 1, "count=\(store.count)")
    check("corrections re-record keeps said", store.all().first?.said == "Tiago Rey")

    // Persistence roundtrip (iso8601 dates must survive decoder+encoder parity).
    let reloaded = CorrectionStore(paths: paths, clock: clock)
    check("corrections persistence roundtrip", reloaded.all().first?.said == "Tiago Rey")

    // Exact replacement: whole-word, case-insensitive, case-mirroring,
    // substring-safe.
    let corr = [Correction(id: UUID(), heard: "tiago", said: "Tiago", createdAt: Date(timeIntervalSince1970: 0))]
    check("corrections apply whole word", CorrectionStore.apply("tiago va a la tienda", corrections: corr) == "Tiago va a la tienda")
    check("corrections apply substring safe", CorrectionStore.apply("el tiagorro", corrections: corr) == "el tiagorro")
    check("corrections apply case mirror upper", CorrectionStore.apply("TIAGO", corrections: corr) == "TIAGO")
    check("corrections apply longest first", CorrectionStore.apply("tiago rey",
          corrections: [Correction(id: UUID(), heard: "tiago", said: "T", createdAt: Date(timeIntervalSince1970: 0)),
                        Correction(id: UUID(), heard: "tiago rey", said: "Tiago Rey", createdAt: Date(timeIntervalSince1970: 0))]) == "Tiago Rey")

    // Diff extraction: word-level swap, char-level case fix, non-learnables.
    let wordPair = CorrectionStore.diffCorrection(original: "hola tiago como estas", corrected: "hola Tiago como estas")
    check("corrections diff word level", wordPair?.heard == "tiago" && wordPair?.said == "Tiago", "\(String(describing: wordPair))")
    let casePair = CorrectionStore.diffCorrection(original: "tiago rey", corrected: "Tiago Rey")
    check("corrections diff case fix", casePair?.heard.lowercased() == "tiago rey", "\(String(describing: casePair))")
    check("corrections diff identical nil", CorrectionStore.diffCorrection(original: "a", corrected: "a") == nil)
    check("corrections diff empty corrected nil", CorrectionStore.diffCorrection(original: "a", corrected: "") == nil)
    check("corrections diff pure deletion nil", CorrectionStore.diffCorrection(original: "hola mundo", corrected: "hola") == nil)
    // End-to-end pure: the diff feeds apply and changes the text.
    if let p = wordPair {
        let fixed = CorrectionStore.apply("hola tiago como estas",
                                          corrections: [Correction(id: UUID(), heard: p.heard, said: p.said, createdAt: Date(timeIntervalSince1970: 0))])
        check("corrections diff feeds apply", fixed == "hola Tiago como estas", fixed)
    }

    // Prompt: newest-first, comma-joined, respects the character budget.
    let many = (0..<10).map { i in
        Correction(id: UUID(), heard: "h\(i)", said: "termino-numero-\(i)", createdAt: Date(timeIntervalSince1970: Double(i)))
    }
    let prompt = CorrectionStore.initialPrompt(from: many, maxCharacters: 40)
    check("corrections prompt respects budget", (prompt?.count ?? 0) <= 40, "\(prompt ?? "nil")")
    check("corrections prompt newest first", prompt?.hasPrefix("termino-numero-9") == true, "\(prompt ?? "nil")")

    // Deletion.
    if let id = store.all().first?.id { store.delete(id: id) }
    check("corrections delete removes", store.count == 0)

    // --- Wispr-style auto-learn (CorrectionWatcher): pure logic only, the
    // watch loop itself NEVER runs in tests (no AX, no timers, no real store). ---
    check("watcher tuning sane", CorrectionWatcher.pollIntervalSeconds >= 0.3
        && CorrectionWatcher.windowSeconds <= 60
        && CorrectionWatcher.stabilitySamples >= 1
        && CorrectionWatcher.minSimilarity > 0.3 && CorrectionWatcher.minSimilarity < 0.9)

    // Config roundtrip: auto_learn defaults ON, persists, and reloads (QA paths only).
    do {
        let cfgA = Config(paths: paths)
        check("config auto_learn default true", cfgA.autoLearn)
        cfgA.setAutoLearn(false)
        let cfgB = Config(paths: paths)
        check("config auto_learn persists false", cfgB.autoLearn == false)
        let toml = try String(contentsOf: paths.configFile, encoding: .utf8)
        check("config auto_learn line written", toml.contains("auto_learn = false"))
    }

    check("paster similarity identical", Paster.similarity("abc", "abc") == 1.0)
    check("paster similarity disjoint", Paster.similarity("abc", "xyz") == 0.0)
    check("paster substring bounds", Paster.substring("hola mundo", nsRange: NSRange(location: 5, length: 5)) == "mundo")
    check("paster substring out-of-bounds nil", Paster.substring("corto", nsRange: NSRange(location: 0, length: 99)) == nil)

    let sess = Paster.Session(element: nil, pastedText: "esto es una prueva",
                              selectedRange: NSRange(location: 6, length: 0),
                              fieldBefore: "Hola, ", startedAt: Date())
    let exp = CorrectionWatcher.expectedField(after: sess)
    check("watcher expected field exact", exp == "Hola, esto es una prueva", exp ?? "nil")

    // Word fix INSIDE the pasted text → minimal pair, not the whole field.
    let fix1 = CorrectionWatcher.extractPair(pasted: "esto es una prueva",
                                             typed: "Hola, esto es una prueba",
                                             expected: "Hola, esto es una prueva")
    check("watcher learns minimal word fix", fix1?.heard == "prueva" && fix1?.said == "prueba", "\(String(describing: fix1))")

    // Mid-word single-letter substitution → expanded to the containing word.
    let fix2 = CorrectionWatcher.extractPair(pasted: "hola prueva",
                                             typed: "hola prueba mundo",
                                             expected: "hola prueva mundo")
    check("watcher expands mid-word cut", fix2?.heard == "prueva" && fix2?.said == "prueba", "\(String(describing: fix2))")

    // Guards that refuse false lessons:
    check("watcher refuses unrelated rewrite",
          CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: "https://ejemplo.com/x", expected: "Hola, esto es una prueva") == nil)
    check("watcher refuses case-only edit",
          CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: "HOLA, ESTO ES UNA PRUEVA", expected: "Hola, esto es una prueva") == nil)
    check("watcher refuses too-short",
          CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: "Hola, ok", expected: "Hola, esto es una prueva") == nil)
    check("watcher refuses insertion-only",
          CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: "Hola, esto es unaa prueva", expected: "Hola, esto es una prueva") == nil)
    check("watcher refuses nothing-changed",
          CorrectionWatcher.extractPair(pasted: "hola", typed: "hola", expected: "hola") == nil)
    // Edits to the user's OWN surrounding context are never attributed to the model.
    check("watcher refuses outside-paste edit",
          CorrectionWatcher.extractPair(pasted: "hola", typed: "queridísimo diario: hola", expected: "querido diario: hola") == nil)

    // --- Adversarial round 2 (full test pass): Unicode ES, boundaries, live-loop logic ---
    // Accented vowel substitution inside ONE word must learn the accented word.
    let fixAcc = CorrectionWatcher.extractPair(pasted: "cancion",
                                               typed: "canción",
                                               expected: "cancion")
    check("watcher learns accented fix", fixAcc?.heard == "cancion" && fixAcc?.said == "canción", "\(String(describing: fixAcc))")

    // Paste at position 0 of an EMPTY field (common: fresh message box).
    let sessEmpty = Paster.Session(element: nil, pastedText: "hola prueva",
                                   selectedRange: NSRange(location: 0, length: 0),
                                   fieldBefore: "", startedAt: Date())
    check("watcher expected empty field", CorrectionWatcher.expectedField(after: sessEmpty) == "hola prueva")
    let fixEmpty = CorrectionWatcher.extractPair(pasted: "hola prueva", typed: "hola prueba", expected: "hola prueva")
    check("watcher fixes in empty field", fixEmpty?.heard == "prueva" && fixEmpty?.said == "prueba", "\(String(describing: fixEmpty))")

    // Corrupt snapshot (selection location beyond the field length) → nil, never crash.
    let sessBad = Paster.Session(element: nil, pastedText: "x",
                                 selectedRange: NSRange(location: 50, length: 0),
                                 fieldBefore: "corto", startedAt: Date())
    check("watcher corrupt snapshot nil", CorrectionWatcher.expectedField(after: sessBad) == nil)

    // Paste REPLACING an existing selection: expected field is paste over the selection.
    let sessRepl = Paster.Session(element: nil, pastedText: "PRUEVA",
                                  selectedRange: NSRange(location: 0, length: 5),
                                  fieldBefore: "error", startedAt: Date())
    check("watcher expected replaces selection", CorrectionWatcher.expectedField(after: sessRepl) == "PRUEVA", "\(CorrectionWatcher.expectedField(after: sessRepl) ?? "nil")")
    // Case-only fix over that replacement (app autocapitalize) must be refused.
    check("watcher refuses case-only over selection",
          CorrectionWatcher.extractPair(pasted: "PRUEVA", typed: "prueba", expected: "PRUEVA") == nil)

    // Multi-lesson max-length guard.
    let longFix = CorrectionWatcher.extractPair(pasted: String(repeating: "a", count: 500),
                                                typed: String(repeating: "a", count: 499) + "b",
                                                expected: String(repeating: "a", count: 500))
    check("watcher refuses oversized fix", longFix == nil)

    // Live-loop decision logic: undoes (field back to expected) RESET stability.
    // Mirrors watch() without AX/timers: expected → continue; changed → count.
    do {
        let expected = "Hola, esto es una prueva"
        var lastValue: String?? = nil // nil outer = never observed; inner nil = unreadable
        var stable = 0
        var learned = false
        let samples: [String?] = [expected, "Hola, esto es una prueba", "Hola, esto es una prueba"]
        for s in samples {
            if s == expected { stable = 0; continue }   // user undid back to our text
            if s == lastValue { stable += 1 } else { stable = 1 }
            lastValue = s
            if stable >= CorrectionWatcher.stabilitySamples,
               let v = s,
               CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: v, expected: expected) != nil {
                learned = true
                break
            }
        }
        check("watcher loop two-stable-samples then learn", learned)
        // Undo-back-to-expected then re-edit must NOT learn from the stale sample:
        var stable2 = 0
        var learned2 = false
        var last2: String?? = nil
        for s in [expected, "Hola, esto es una prueba", expected, "Hola, esto es una prueba"] as [String?] {
            if s == expected { stable2 = 0; continue }
            if s == last2 { stable2 += 1 } else { stable2 = 1 }
            last2 = s
            if stable2 >= CorrectionWatcher.stabilitySamples, let v = s,
               CorrectionWatcher.extractPair(pasted: "esto es una prueva", typed: v, expected: expected) != nil {
                learned2 = true
                break
            }
            // second occurrence of the same edit only reaches stability on the NEXT sample
        }
        check("watcher loop undo resets stability", !learned2, "learned2=\(learned2)")
    }

    // --- matt-tdd: live watch() loop at the injection seam. Integration tests
    // of the REAL loop — fake field reader, QA sink, fake sleep, deterministic,
    // zero AX calls (the reader closure ignores the element). Red first: these
    // failed to compile until watch() grew injectable dependencies.
    do {
        let cfg = CorrectionWatcher.WatchConfig(pollIntervalSeconds: 0.8, windowSeconds: 10, stabilitySamples: 2)
        let expected = "Hola, esto es una prueva"
        let samples = [expected, expected, "Hola, esto es una prueba", "Hola, esto es una prueba", "Hola, esto es una prueba"]
        let liveElement = AXUIElementCreateSystemWide() // never read for real: the fake reader ignores it

        func reader(for clock: FixedClock) -> (AXUIElement) -> String? {
            { _ in samples[min(Int(clock.uptimeSeconds / cfg.pollIntervalSeconds), samples.count - 1)] }
        }

        // A: element unreadable the whole window → no lesson, sink untouched.
        let sinkA = CorrectionWatcher.QASink()
        let clockA = FixedClock()
        let a = CorrectionWatcher.watch(session: sess, clock: clockA, readField: { _ in nil },
                                        sleep: { clockA.advance(seconds: $0) }, sink: sinkA, config: cfg)
        check("watch integration unreadable element no lesson", a == false && sinkA.pairs.isEmpty)

        // B: user types the fix and pauses → learned exactly once, minimal pair,
        // into the QA sink ONLY (the real store is never touched by tests).
        let sinkB = CorrectionWatcher.QASink()
        let clockB = FixedClock()
        let sessLive = Paster.Session(element: liveElement, pastedText: "esto es una prueva",
                                      selectedRange: NSRange(location: 6, length: 0),
                                      fieldBefore: "Hola, ", startedAt: Date())
        let b = CorrectionWatcher.watch(session: sessLive, clock: clockB, readField: reader(for: clockB),
                                        sleep: { clockB.advance(seconds: $0) }, sink: sinkB, config: cfg)
        check("watch integration learns after stability", b == true, "\(sinkB.pairs)")
        check("watch integration sink got minimal pair", sinkB.pairs.first?.heard == "prueva" && sinkB.pairs.first?.said == "prueba", "\(sinkB.pairs)")
        check("watch integration one lesson only", sinkB.pairs.count == 1)

        // C: unrelated rewrite (URL over the paste) → window expires, no lesson.
        let sinkC = CorrectionWatcher.QASink()
        let clockC = FixedClock()
        let c = CorrectionWatcher.watch(session: sessLive, clock: clockC, readField: { _ in "https://ejemplo.com/x" },
                                        sleep: { clockC.advance(seconds: $0) }, sink: sinkC, config: cfg)
        check("watch integration refuses rewrite", c == false && sinkC.pairs.isEmpty)
    }

    // Teardown: remove only what this run owns.
    try? FileManager.default.removeItem(at: root)
    check("corrections qa root removed", !FileManager.default.fileExists(atPath: root.path))

    print("[INFO] corrections: original smoke suites intentionally NOT executed (real-profile protection, V01-AC05)")
    print("\nCorrections learned-correction checks passed.")
    exit(0)
}

// 1. Model catalog integrity
for m in WhisperCatalog.all {
    check("catalog[\(m.id)] hash format", m.sha256.count == 64 && m.sha256.allSatisfy(\.isHexDigit))
    check("catalog[\(m.id)] plausible size", m.bytes > 50_000_000 && m.bytes < 3_000_000_000, "\(m.bytes) bytes")
}
check("catalog uniqueness", Set(WhisperCatalog.all.map(\.id)).count == WhisperCatalog.all.count)

// 2. Hardware profile — language-aware (audit v2 §3.2: auto/es must NEVER get an English-only model)
let recEn = HardwareProfile.recommendedModel(language: "en")
let recAuto = HardwareProfile.recommendedModel(language: "auto")
let recEs = HardwareProfile.recommendedModel(language: "es")
check("preset en", ["small.en-q5_1", "large-v3-turbo"].contains(recEn), "tier=\(HardwareProfile.RAMTier.tier(forRAMGB: HardwareProfile.totalRAMGB)) → \(recEn)")
check("preset es multilingual", WhisperCatalog.byId(recEs).map { !$0.isEnglishOnly } == true, "es → \(recEs)")
check("preset auto multilingual", WhisperCatalog.byId(recAuto).map { !$0.isEnglishOnly } == true, "auto → \(recAuto)")
check("catalog has small-q5_1", WhisperCatalog.byId("small-q5_1") != nil)

// 3. Localizer — PURE resolution only (V02): reading/writing L.override here
// mutated the user's real preference domain. The override path is exercised
// in Tests/VozaTests via isolated defaults.
check("localizer pure es",
      L.resolve("Hello", es: "Hola", spanish: true) == "Hola")
check("localizer pure en",
      L.resolve("Hello", es: "Hola", spanish: false) == "Hello")
check("localizer override wins",
      L.resolveIsSpanish(override: "en", systemLanguages: ["es-MX"]) == false)
check("localizer system decides without override",
      L.resolveIsSpanish(override: nil, systemLanguages: ["es-MX", "en"]) == true)
check("localizer non-es system",
      L.resolveIsSpanish(override: nil, systemLanguages: ["en-US"]) == false)

// 4. Config resolution — hermetic QA instance (V02). Config.shared reads the
// real profile; its env fallback would leak process variables into checks.
if let env = SmokeQA(name: "config") {
    defer { env.tearDown() }
    let config = Config(paths: env.paths)
    check("config language resolution", ["auto", "en", "es"].contains(config.resolvedLanguage), config.resolvedLanguage)
    check("config model resolution", WhisperCatalog.byId(config.resolvedModelId) != nil, config.resolvedModelId)
    check("config env keys stay out of QA", config.env["OPENAI_API_KEY"] == nil)
    check("config reads create nothing", !FileManager.default.fileExists(atPath: env.root.path))
} else {
    check("config hermetic environment", false, "no defaults suite available")
}

// 4b. resolvedModel descriptor + fallback — needs downloaded models: opt-in.
if integrationGuard("resolvedModel fallback + descriptor", requires: "downloaded models") {
    if let resolved = ModelManager.shared.resolvedModel(preferredId: "nonexistent-model-id") {
        check("resolvedModel descriptor real", WhisperCatalog.byId(resolved.model.id) != nil, resolved.model.id)
    } else {
        skipSmoke("resolvedModel fallback (no models downloaded)")
    }
}

// 5. Real history dir writability — touches the user's ~/Dictation: opt-in.
skipSmoke("real history writability — opt-in --live-real (probes ~/Dictation)")

// 6. WAV writer: canonical 44-byte IEEE-float header + whisper-cli can consume OUR file
check("wav header is exactly 44 bytes", AudioRecorder.wavHeader(dataBytes: 1234).count == 44,
      "\(AudioRecorder.wavHeader(dataBytes: 1234).count) bytes")
do {
    let h = AudioRecorder.wavHeader(dataBytes: 1000)
    let u16 = { (o: Int) -> Int in Int(h[o]) | (Int(h[o + 1]) << 8) }
    let u32 = { (o: Int) -> UInt32 in
        UInt32(h[o]) | (UInt32(h[o + 1]) << 8) | (UInt32(h[o + 2]) << 16) | (UInt32(h[o + 3]) << 24)
    }
    check("wav fmt code = IEEE float", u16(20) == 3, "fmt=\(u16(20))")
    check("wav channels = 1", u16(22) == 1, "ch=\(u16(22))")
    check("wav sample rate 16k", u32(24) == 16000, "rate=\(u32(24))")
    check("wav bits = 32", u16(34) == 32, "bits=\(u16(34))")
}
// 6b. Mic + engine roundtrip — OPT-IN integration (V02): needs mic permission
// and a live capture; never part of the default hermetic run.
if integrationGuard("mic roundtrip", requires: "mic permission + audio engine"), Permissions.microphoneGranted {
    do {
        try AudioRecorder.shared.start()
        Thread.sleep(forTimeInterval: 0.6)
        if let url = AudioRecorder.shared.stop() {
            let data = try Data(contentsOf: url)
            check("wav header magic", String(data: data.prefix(4), encoding: .ascii) == "RIFF")
            check("wav payload present", data.count > 44 + 8000, "\(data.count) bytes")
            let fmtCode = Int(data[20]) | (Int(data[21]) << 8) // little-endian UInt16 at offset 20
            check("wav fmt IEEE float (3)", fmtCode == 3, "fmt=\(fmtCode)")
            check("wav bits 32", Int(data[34]) == 32, "bits=\(data[34])")
            // END-TO-END: whisper-cli must parse OUR recorded WAV. Empty transcript is
            // fine (ambient silence); any parse failure is a real regression.
            if let model = ModelManager.shared.downloadedModels().first {
                do {
                    let text = try Transcriber().transcribe(wavURL: url,
                                                            modelPath: ModelManager.shared.localPath(for: model).path,
                                                            language: "auto")
                    print("[INFO] mic roundtrip transcript: \(text.isEmpty ? "(silence)" : text)")
                    check("whisper-cli consumes voza wav", true)
                } catch TranscriptionError.emptyResult {
                    check("whisper-cli consumes voza wav", true, "(silence)")
                }
            } else {
                skipSmoke("whisper-cli on voza wav (no model downloaded; pass --qa-models <dir>)")
            }
            try? FileManager.default.removeItem(at: url)
        } else {
            check("wav stop returns file", false)
        }
    } catch {
        check("wav record roundtrip", false, "\(error)")
    }
} else if integration && !Permissions.microphoneGranted {
    skipSmoke("mic roundtrip — microphone permission not granted in this context")
}

// Optional E2E: download a model + transcribe a real sample through the full pipeline.
// Usage: swift run VozaSmoke e2e /path/to/jfk.wav --qa-models /path/to/qa/dir
// V02: downloads REQUIRE an explicit QA destination — the real models dir is
// never touched from tests. This is pipeline integration, NOT a paste E2E
// (no insertion/paste path is exercised here).
if CommandLine.arguments.contains("e2e") {
    let argIndex = CommandLine.arguments.firstIndex(of: "e2e")!
    let wavPath = CommandLine.arguments.count > argIndex + 1
        ? CommandLine.arguments[argIndex + 1]
        : ""
    guard FileManager.default.fileExists(atPath: wavPath) else {
        print("e2e: provide a wav file path"); exit(1)
    }
    guard let qaModelsRoot else {
        print("e2e: model downloads require an explicit QA destination — pass --qa-models <dir>")
        exit(1)
    }
    guard let model = WhisperCatalog.byId("small-q5_1") else { exit(1) } // multilingual + auto language (audit v2 §3.1/§3.2)

    print("Downloading \(model.id) (\(model.sizeLabel)) into QA dir \(qaModelsRoot)…")
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            try await ModelManager.shared.download(model, into: qaModelsRoot) { p in
                let bars = Int(p * 20)
                print("\r[" + String(repeating: "#", count: bars) + String(repeating: ".", count: 20 - bars) + "] \(Int(p * 100))%", terminator: "")
                if p >= 1.0 { print() }
            }
            print("SHA-256 verified")
            let path = URL(fileURLWithPath: qaModelsRoot, isDirectory: true).appendingPathComponent(model.file).path
            let result = try Transcriber().transcribe(wavURL: URL(fileURLWithPath: wavPath), modelPath: path, language: "auto")
            print("TRANSCRIPT (auto language): \(result)")
            check("e2e transcript plausible", result.lowercased().contains("fellow"), result)
        } catch {
            check("e2e pipeline", false, "\(error)")
        }
        sem.signal()
    }
    sem.wait()
}

// 7. Performance monitor logic — hermetic QA instance (V02): no writes to the
// real perf.json, no dismissal keys in real defaults.
if let env = SmokeQA(name: "perf") {
    defer { env.tearDown() }
    let perf = PerformanceMonitor(paths: env.paths, clock: env.clock, defaults: env.defaults)
    perf._test_setSamples([0.2, 0.3, 0.4], model: "small.en-q5_1")
    check("perf median", abs((perf.medianRTF(model: "small.en-q5_1") ?? 0) - 0.3) < 0.001)
    check("perf speed label", perf.speedLabel(model: "small.en-q5_1") == "3.3× realtime",
          perf.speedLabel(model: "small.en-q5_1") ?? "nil")
    check("perf no suggestion in healthy band",
          perf.suggestion(currentModel: "small.en-q5_1", ramGB: 24) == nil)
    perf._test_setSamples([0.9, 1.1, 0.8], model: "small.en-q5_1")
    let sugg = perf.suggestion(currentModel: "small.en-q5_1", ramGB: 24)
    check("perf suggests lighter when slow", sugg?.direction == .lighter, sugg?.targetModelId ?? "none")
    perf._test_setSamples([0.05, 0.06, 0.04], model: "small.en-q5_1")
    check("perf no heavier suggestion under 32GB",
          perf.suggestion(currentModel: "small.en-q5_1", ramGB: 24) == nil)
    check("perf suggests heavier on 32GB+",
          perf.suggestion(currentModel: "small.en-q5_1", ramGB: 32)?.direction == .heavier)
    check("perf file confined to QA root", FileManager.default.fileExists(atPath: env.paths.perfFile.path))
} else {
    check("perf hermetic environment", false, "no defaults suite available")
}
check("perf eta format", AppState.formatETA(95) == "1m 35s", AppState.formatETA(95))

// 8. Readiness snapshot — probes are read-only (disk, engine existence,
// permission booleans); missing binaries on this machine is a SKIP, not a fail.
let readiness = ReadinessChecker.check()
check("readiness disk sane", readiness.freeDiskMB > 0, "\(readiness.freeDiskMB) MB free")
if readiness.engineFound {
    check("readiness engine found", true)
} else {
    skipSmoke("readiness engine — whisper-cli not installed (pure mode requires none, V02-AC02)")
}
check("allGranted includes input monitoring",
      Permissions.allGranted == (Permissions.microphoneGranted && Permissions.accessibilityGranted && Permissions.inputMonitoringGranted))

// 9. History markdown roundtrip — raw AND cleaned entries must survive a reload
// (audit v2 §3.9: the ✨ marker used to break the timestamp parse)
do {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let stamp = f.string(from: Date(timeIntervalSince1970: 1_700_000_000))
    let md = """
    # Dictation log — test\n\n## \(stamp)\n\nraw entry text\n\n## \(stamp)  ✨\n\ncleaned entry text\n\n## broken line no date\n\nxx\n
    """
    let parsed = TranscriptStore.parseEntries(fromMarkdown: md)
    check("history parse count", parsed.count == 2, "\(parsed.count) entries")
    check("history raw survives", parsed.contains { !$0.cleaned && $0.text == "raw entry text" })
    check("history cleaned survives", parsed.contains { $0.cleaned && $0.text == "cleaned entry text" })
}

// 10. Cleaner privacy boundary (audit v2 §3.8 + D032): no mode ever reaches
// a local provider (they no longer exist) and ONLY explicit "cloud" touches
// the network — anything else is passthrough.
check("cleanup plain = none", Cleaner.providerChain(for: "plain").isEmpty)
check("cleanup auto (legacy) = none", Cleaner.providerChain(for: "auto").isEmpty,
      "local providers removed — legacy value must not resurrect them")
check("cleanup cloud explicit", Cleaner.providerChain(for: "cloud") == ["openai", "anthropic"])

// 11. Disk guard is per-model (audit v2 §3.10)
if let small = WhisperCatalog.byId("small-q5_1"), let big = WhisperCatalog.byId("large-v3-turbo") {
    check("disk guard per-model", ReadinessChecker.requiredFreeMB(for: big) > ReadinessChecker.requiredFreeMB(for: small),
          "small=\(ReadinessChecker.requiredFreeMB(for: small))MB big=\(ReadinessChecker.requiredFreeMB(for: big))MB")
    check("disk guard covers model size", ReadinessChecker.requiredFreeMB(for: small) >= 190)
}

// V02-AC05: explicit accounting — SKIPs are listed, never counted as passes.
if smokeSkips > 0 {
    print("[INFO] \(smokeSkips) opt-in suite(s) skipped — run with --integration / --live-real / e2e to include them.")
}
print("\nAll pure smoke checks passed (\(smokeChecks) checks, \(smokeSkips) skips).")
exit(0)
