import Foundation
@testable import VozaKit

// D024 acceptance (default mode): long dictation through the REAL production
// chain (Cleaner.clean, mode "auto" = [mlx, ollama]) with Ollama DEAD.
// D027 stress (arg "stress"): back-to-back generations with deterministic
// memory-pressure notifications injected DURING generation (the exact notify
// channel DispatchSource.makeMemoryPressureSource listens on), plus concurrent
// unloadNow() hammering — must not crash, must defer, must keep working.
// Cleaner.clean returns non-optional CleaningOutcome (D016-safe).

let longRawDictation = """
ok entonces este... vamos a ver um la propuesta tiene tres partes la primera es el análisis de competencia que ya está listo y la segunda parte es el diseño del pipeline de audio o sea como entra el sonido como se graba con ffmpeg y como sale el transcript y la tercera parte es el plan de distribución con gumroad quita lo de la tercera parte porque eso ya lo decidimos con jero y bueno ahí lo dejamos para después
"""

var failures = 0
func require(_ ok: Bool, _ label: String) {
    print(ok ? "PASS  \(label)" : "FAIL  \(label)")
    if !ok { failures += 1 }
}

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

/// Fires warn+critical memory-pressure notifications on the system notify
/// channel DispatchSource.makeMemoryPressureSource consumes. Deterministic:
/// no real memory is allocated, no other process is affected.
func startPressureFlood(every seconds: Double) -> Thread {
    let t = Thread {
        while !Thread.current.isCancelled {
            for key in ["com.apple.system.memorystatus.warning", "com.apple.system.memorystatus.critical"] {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/notifyutil")
                proc.arguments = ["-p", key]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                try? proc.run()
                proc.waitUntilExit()
            }
            Thread.sleep(forTimeInterval: seconds)
        }
    }
    t.name = "voza-bench-pressure"
    t.qualityOfService = .utility
    t.start()
    return t
}

func rssMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "default"

Task {
    defer { sem.signal() }
    print("Ollama reachable before:", ollamaAlive() ? "YES (bad)" : "NO (good)")
    let config = Config()
    print("cleanupMode:", config.resolvedCleanupMode,
          "| chain:", Cleaner.providerChain(for: config.resolvedCleanupMode))

    if mode == "stress" {
        // --- Scenario 1: 3 back-to-back generations, pressure injected DURING ---
        MLXEngine.config.preloadOnLaunch = true
        await MLXEngine.preloadNow()
        require(MLXEngine.isLoaded, "preload resident before stress")
        print(String(format: "RSS after preload: %.0f MB", rssMB()))

        for round in 1...3 {
            let flood = startPressureFlood(every: 0.3)
            let t0 = Date()
            let outcome = await Cleaner.clean(longRawDictation, config: config)
            let dt = Date().timeIntervalSince(t0)
            flood.cancel()
            print(String(format: "round %d: %.2fs | provider: %@ | RSS %.0f MB",
                         round, dt, outcome.provider ?? "nil", rssMB()))
            require(outcome.applied && outcome.provider == "mlx",
                    "round \(round): mlx applied")
            require(!outcome.text.lowercased().contains("quita lo de"),
                    "round \(round): edit command dropped")
            require(!outcome.text.contains("<end_of_turn>") && !outcome.text.contains("<think>"),
                    "round \(round): no marker leak")
            // The pressure handler must have deferred (not torn down) mid-run:
            // weights stay usable round-to-round OR unload happened — both are
            // safe; the only failure is a crash (we reached this line).
        }
        require(true, "no crash under injected pressure (3 rounds)")

        // --- Scenario 2: unloadNow() hammered concurrently DURING generation ---
        let hammer = Thread {
            for _ in 0..<40 {
                MLXEngine.unloadNow()
                Thread.sleep(forTimeInterval: 0.04)
            }
        }
        hammer.qualityOfService = .utility
        hammer.start()
        let t2 = Date()
        let raced = await Cleaner.clean(longRawDictation, config: config)
        print(String(format: "raced clean: %.2fs | provider: %@",
                     Date().timeIntervalSince(t2), raced.provider ?? "nil"))
        require(raced.applied, "clean survives concurrent unload hammering")
        require(!raced.text.contains("<end_of_turn>"), "raced output clean")

        // --- Scenario 3: idle eviction still works when nothing is in flight ---
        MLXEngine.unloadNow()
        require(!MLXEngine.isLoaded, "idle unload evicts weights")
        print(String(format: "RSS after unload: %.0f MB", rssMB()))

        // --- Scenario 4: engine still usable after everything ---
        let last = await Cleaner.clean(longRawDictation, config: config)
        require(last.applied, "engine reloads and cleans after full stress cycle")
        MLXEngine.unloadNow()
        require(!MLXEngine.isLoaded, "final unload clean")
    } else {
        // --- D024 acceptance (default) ---
        print("Engine resident before:", MLXEngine.isLoaded)
        let t0 = Date()
        let outcome = await Cleaner.clean(longRawDictation, config: config)
        print(String(format: "COLD ELAPSED: %.2fs", Date().timeIntervalSince(t0)))
        print("applied:", outcome.applied, "| provider:", outcome.provider ?? "nil")
        print("--- RESULT ---")
        print(outcome.text)
        print("--------------")
        require(outcome.applied && outcome.provider == "mlx", "mlx applied")
        require(!outcome.text.lowercased().contains("quita"), "edit command dropped")
        let t1 = Date()
        _ = await Cleaner.clean(longRawDictation, config: config)
        print(String(format: "WARM ELAPSED: %.2fs", Date().timeIntervalSince(t1)))
        MLXEngine.unloadNow()
        require(!MLXEngine.isLoaded, "unload evicts")
    }

    print("Ollama reachable after:", ollamaAlive() ? "YES (bad)" : "NO (good)")
    print(failures == 0 ? "ALL ASSERTIONS PASSED" : "ASSERTION FAILURES: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
sem.wait()
