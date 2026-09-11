import Foundation
import VozaKit

// D024 bench: real prompt v3, real engine, same M4 Pro. Temporary harness.
let prompt = """
You clean dictated transcripts. Apply ONLY these transformations:
1. Fix punctuation and capitalization — always capitalize the first word of the text and of each sentence.
2. Remove filler words and stutters.
3. EDIT COMMANDS: phrases like "quita lo de X", "quita eso", "borra lo último", "no, di mejor X" are spoken EDIT COMMANDS targeting the dictation itself — apply them (delete/rephrase the targeted part) and NEVER output the command itself.
4. Keep the speaker's language, meaning and tone. Do not rewrite, translate or add anything.
Output ONLY the cleaned text — no quotes, no commentary.
"""
let raw = "es que a ver te estoy hablando ahorita de mi reflexión y está interesante solamente me gustaría checar cómo funciona y quita lo de cómo funciona y me gustaría checar si vale la pena hacer el producto checando lo que yo tengo en type whisper porque type whisper es muy rápido"

let sem = DispatchSemaphore(value: 0)
Task {
    print("COLD: descargando/cargando \(MLXEngine.config.model.rawValue)…")
    let c0 = Date()
    let out = await MLXEngine.complete(raw, systemPrompt: prompt)
    print("COLD total (descarga+load+gen): \(String(format: "%.1f", Date().timeIntervalSince(c0)))s | gen only: \(String(format: "%.2f", out?.generateSeconds ?? -1))s")
    if let o = out { print("→", o.rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320)) }
    else { print("NIL RESULT") }
    let w0 = Date()
    let out2 = await MLXEngine.complete(raw, systemPrompt: prompt)
    print("WARM total: \(String(format: "%.2f", Date().timeIntervalSince(w0)))s | gen: \(String(format: "%.2f", out2?.generateSeconds ?? -1))s")
    if let o = out2 { print("→", o.rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320)) }
    print("isLoaded:", MLXEngine.isLoaded)
    MLXEngine.unloadNow()
    print("isLoaded tras unload:", MLXEngine.isLoaded)
    sem.signal()
}
sem.wait()
