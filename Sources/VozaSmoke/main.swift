import Foundation
@testable import VozaKit

// Lightweight verification suite — runs with the CommandLineTools toolchain
// (no XCTest available there). Exits non-zero on first failure.

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    let icon = condition ? "PASS" : "FAIL"
    print("[\(icon)] \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !condition { exit(1) }
}

// 1. Model catalog integrity
for m in WhisperCatalog.all {
    check("catalog[\(m.id)] hash format", m.sha256.count == 64 && m.sha256.allSatisfy(\.isHexDigit))
    check("catalog[\(m.id)] plausible size", m.bytes > 50_000_000 && m.bytes < 3_000_000_000, "\(m.bytes) bytes")
}
check("catalog uniqueness", Set(WhisperCatalog.all.map(\.id)).count == WhisperCatalog.all.count)

// 2. Hardware profile
let ram = HardwareProfile.totalRAMGB
let rec = HardwareProfile.recommendedModel()
check("hardware preset", ["small.en-q5_1", "small.en", "large-v3-turbo"].contains(rec), "ram=\(ram)GB → \(rec)")

// 3. Localizer
L.override = "es"
check("localizer es", L.t("Hello", es: "Hola") == "Hola")
L.override = "en"
check("localizer en", L.t("Hello", es: "Hola") == "Hello")
L.override = nil

// 4. Config resolved values
let config = Config.shared
check("config language resolution", ["en", "es"].contains(config.resolvedLanguage), config.resolvedLanguage)
check("config model resolution", WhisperCatalog.byId(config.resolvedModelId) != nil, config.resolvedModelId)
check("config whisper binary detectable", Transcriber.locateBinary() != nil, Transcriber.locateBinary() ?? "none")

// 5. Log directory writable
let dir = TranscriptStore.logDirectory
check("log dir exists", FileManager.default.fileExists(atPath: dir.path), dir.path)
check("log dir writable", FileManager.default.isWritableFile(atPath: dir.path))

// 6. WAV writer sanity: record briefly if mic permission already granted
if Permissions.microphoneGranted {
    do {
        try AudioRecorder.shared.start()
        Thread.sleep(forTimeInterval: 0.6)
        if let url = AudioRecorder.shared.stop() {
            let data = try Data(contentsOf: url)
            let header = String(data: data.prefix(4), encoding: .ascii) ?? ""
            check("wav header magic", header == "RIFF", header)
            check("wav payload present", data.count > 44 + 8000, "\(data.count) bytes")
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
    guard let model = WhisperCatalog.byId("small.en-q5_1") else { exit(1) }

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
            let result = try Transcriber().transcribe(wavURL: URL(fileURLWithPath: wavPath), modelPath: path, language: "en")
            print("TRANSCRIPT: \(result)")
            check("e2e transcript plausible", result.lowercased().contains("fellow"), result)
        } catch {
            check("e2e pipeline", false, "\(error)")
        }
        sem.signal()
    }
    sem.wait()
}

print("\nAll smoke checks passed.")
