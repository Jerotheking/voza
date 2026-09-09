import Foundation
@testable import VozaKit

// Lightweight verification suite — runs with the CommandLineTools toolchain
// (no XCTest available there). Exits non-zero on first failure.

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    let icon = condition ? "PASS" : "FAIL"
    print("[\(icon)] \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { exit(1) }
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

// 1. Model catalog integrity
for m in WhisperCatalog.all {
    check("catalog[\(m.id)] hash format", m.sha256.count == 64 && m.sha256.allSatisfy(\.isHexDigit))
    check("catalog[\(m.id)] plausible size", m.bytes > 50_000_000 && m.bytes < 3_000_000_000, "\(m.bytes) bytes")
}
check("catalog uniqueness", Set(WhisperCatalog.all.map(\.id)).count == WhisperCatalog.all.count)

// 2. Hardware profile — language-aware (audit v2 §3.2: auto/es must NEVER get an English-only model)
let ram = HardwareProfile.totalRAMGB
let recEn = HardwareProfile.recommendedModel(language: "en")
let recAuto = HardwareProfile.recommendedModel(language: "auto")
let recEs = HardwareProfile.recommendedModel(language: "es")
check("preset en", ["small.en-q5_1", "large-v3-turbo"].contains(recEn), "ram=\(ram)GB → \(recEn)")
check("preset es multilingual", WhisperCatalog.byId(recEs).map { !$0.isEnglishOnly } == true, "es → \(recEs)")
check("preset auto multilingual", WhisperCatalog.byId(recAuto).map { !$0.isEnglishOnly } == true, "auto → \(recAuto)")
check("catalog has small-q5_1", WhisperCatalog.byId("small-q5_1") != nil)

// 3. Localizer
L.override = "es"
check("localizer es", L.t("Hello", es: "Hola") == "Hola")
L.override = "en"
check("localizer en", L.t("Hello", es: "Hola") == "Hello")
L.override = nil

// 4. Config resolved values
let config = Config.shared
check("config language resolution", ["auto", "en", "es"].contains(config.resolvedLanguage), config.resolvedLanguage)
if config.language == "auto" {
    // The speech language must not be derived from the UI language (audit v2 §3.1).
    L.override = "es"
    check("auto stays auto regardless of UI", config.resolvedLanguage == "auto", config.resolvedLanguage)
    L.override = "en"
    check("auto stays auto regardless of UI (en)", config.resolvedLanguage == "auto", config.resolvedLanguage)
    L.override = nil
}
check("config model resolution", WhisperCatalog.byId(config.resolvedModelId) != nil, config.resolvedModelId)
check("config whisper binary detectable", Transcriber.locateBinary() != nil, Transcriber.locateBinary() ?? "none")

// 4b. Model resolution returns the REAL descriptor (audit v2 §3.3)
if let resolved = ModelManager.shared.resolvedModel(preferredId: "nonexistent-model-id") {
    check("resolvedModel descriptor real", WhisperCatalog.byId(resolved.model.id) != nil, resolved.model.id)
} else {
    print("[SKIP] resolvedModel (no models downloaded)")
}

// 5. Log directory writable
let dir = TranscriptStore.logDirectory
check("log dir exists", FileManager.default.fileExists(atPath: dir.path), dir.path)
check("log dir writable", FileManager.default.isWritableFile(atPath: dir.path))

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
if Permissions.microphoneGranted {
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
                print("[SKIP] whisper-cli on voza wav (no model downloaded yet)")
            }
            try? FileManager.default.removeItem(at: url)
        } else {
            check("wav stop returns file", false)
        }
    } catch {
        check("wav record roundtrip", false, "\(error)")
    }
} else {
    print("[SKIP] mic roundtrip (no permission in this context)")
}

// Optional E2E: download a model + transcribe a real sample through the full pipeline.
// Usage: swift run VozaSmoke e2e /path/to/jfk.wav
if CommandLine.arguments.contains("e2e") {
    let argIndex = CommandLine.arguments.firstIndex(of: "e2e")!
    let wavPath = CommandLine.arguments.count > argIndex + 1
        ? CommandLine.arguments[argIndex + 1]
        : ""
    guard FileManager.default.fileExists(atPath: wavPath) else {
        print("e2e: provide a wav file path"); exit(1)
    }
    guard let model = WhisperCatalog.byId("small-q5_1") else { exit(1) } // multilingual + auto language (audit v2 §3.1/§3.2)

    print("Downloading \(model.id) (\(model.sizeLabel))…")
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            try await ModelManager.shared.download(model) { p in
                let bars = Int(p * 20)
                print("\r[" + String(repeating: "#", count: bars) + String(repeating: ".", count: 20 - bars) + "] \(Int(p * 100))%", terminator: "")
                if p >= 1.0 { print() }
            }
            print("SHA-256 verified")
            let path = ModelManager.shared.localPath(for: model).path
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

// 7. Performance monitor logic
PerformanceMonitor.shared._test_clear()
PerformanceMonitor.shared._test_setSamples([0.2, 0.3, 0.4], model: "small.en-q5_1")
check("perf median", abs((PerformanceMonitor.shared.medianRTF(model: "small.en-q5_1") ?? 0) - 0.3) < 0.001)
check("perf speed label", PerformanceMonitor.shared.speedLabel(model: "small.en-q5_1") == "3.3× realtime",
      PerformanceMonitor.shared.speedLabel(model: "small.en-q5_1") ?? "nil")
check("perf no suggestion in healthy band",
      PerformanceMonitor.shared.suggestion(currentModel: "small.en-q5_1", ramGB: 24) == nil)
PerformanceMonitor.shared._test_setSamples([0.9, 1.1, 0.8], model: "small.en-q5_1")
let sugg = PerformanceMonitor.shared.suggestion(currentModel: "small.en-q5_1", ramGB: 24)
check("perf suggests lighter when slow", sugg?.direction == .lighter, sugg?.targetModelId ?? "none")
PerformanceMonitor.shared._test_setSamples([0.05, 0.06, 0.04], model: "small.en-q5_1")
check("perf no heavier suggestion under 32GB",
      PerformanceMonitor.shared.suggestion(currentModel: "small.en-q5_1", ramGB: 24) == nil)
check("perf suggests heavier on 32GB+",
      PerformanceMonitor.shared.suggestion(currentModel: "small.en-q5_1", ramGB: 32)?.direction == .heavier)
PerformanceMonitor.shared._test_clear()
check("perf eta format", AppState.formatETA(95) == "1m 35s", AppState.formatETA(95))

// 8. Readiness snapshot
let readiness = ReadinessChecker.check()
check("readiness disk sane", readiness.freeDiskMB > 0, "\(readiness.freeDiskMB) MB free")
check("readiness engine", readiness.engineFound)
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

// 10. Cleaner privacy boundary (audit v2 §3.8): "auto" must NEVER chain to cloud
let autoChain = Cleaner.providerChain(for: "auto")
check("cleanup auto = local only", autoChain == ["ollama"], "\(autoChain)")
check("cleanup ollama = local only", Cleaner.providerChain(for: "ollama") == ["ollama"])
check("cleanup plain = none", Cleaner.providerChain(for: "plain").isEmpty)
check("cleanup cloud explicit", Cleaner.providerChain(for: "cloud") == ["openai", "anthropic"])

// 11. Disk guard is per-model (audit v2 §3.10)
if let small = WhisperCatalog.byId("small-q5_1"), let big = WhisperCatalog.byId("large-v3-turbo") {
    check("disk guard per-model", ReadinessChecker.requiredFreeMB(for: big) > ReadinessChecker.requiredFreeMB(for: small),
          "small=\(ReadinessChecker.requiredFreeMB(for: small))MB big=\(ReadinessChecker.requiredFreeMB(for: big))MB")
    check("disk guard covers model size", ReadinessChecker.requiredFreeMB(for: small) >= 190)
}

print("\nAll smoke checks passed.")
