import Foundation
@testable import VozaKit

// D024 acceptance: long dictation through the REAL production chain
// (Cleaner.clean, mode "auto" = [mlx, ollama]) with Ollama DEAD.
// Proves: mlx-first, Ollama never contacted, quality, cold vs warm latency,
// eviction. Cleaner.clean returns non-optional CleaningOutcome (D016-safe).

let longRawDictation = """
ok entonces este... vamos a ver um la propuesta tiene tres partes la primera es el análisis de competencia que ya está listo y la segunda parte es el diseño del pipeline de audio o sea como entra el sonido como se graba con ffmpeg y como sale el transcript y la tercera parte es el plan de distribución con gumroad quita lo de la tercera parte porque eso ya lo decidimos con jero y bueno ahí lo dejamos para después
"""

let sem = DispatchSemaphore(value: 0)

func ollamaAlive() -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    proc.arguments = ["-s", "--max-time", "2", "http://127.0.0.1:11434/api/version"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "").contains("version")
}

Task {
    print("Ollama reachable before test:", ollamaAlive() ? "YES (bad)" : "NO (good)")
    print("Engine resident before:", MLXEngine.isLoaded)

    let config = Config()
    print("cleanupMode:", config.resolvedCleanupMode, "| chain:", Cleaner.providerChain(for: config.resolvedCleanupMode))

    let t0 = Date()
    let outcome = await Cleaner.clean(longRawDictation, config: config)
    print(String(format: "COLD ELAPSED: %.2fs", Date().timeIntervalSince(t0)))
    print("applied:", outcome.applied, "| provider:", outcome.provider ?? "nil")
    print("--- RESULT ---")
    print(outcome.text)
    print("--------------")
    let hasCommand = outcome.text.lowercased().contains("quita")
    let hasMarker = outcome.text.contains("end_of_turn") || outcome.text.contains("<think>")
    print("edit-command correctly dropped:", !hasCommand ? "YES" : "NO")
    print("markers leaked:", hasMarker ? "YES (BAD)" : "NO")

    // Warm pass: resident weights — the steady state users live in.
    let t1 = Date()
    let warm = await Cleaner.clean(longRawDictation, config: config)
    print(String(format: "WARM ELAPSED: %.2fs", Date().timeIntervalSince(t1)))
    print("WARM provider:", warm.provider ?? "nil")

    print("Ollama reachable after test:", ollamaAlive() ? "YES (bad)" : "NO (good)")
    print("Engine resident after:", MLXEngine.isLoaded)
    MLXEngine.unloadNow()
    print("Engine resident after unload:", MLXEngine.isLoaded)
    sem.signal()
}
sem.wait()
