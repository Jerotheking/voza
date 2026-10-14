import Foundation

enum TranscriptionError: LocalizedError {
    case binaryNotFound
    case modelNotFound
    case transcriptionFailed(String)
    case emptyResult
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return L.t("whisper.cpp not found. Reinstall Voza or set a binary in Advanced settings.",
                       es: "whisper.cpp no encontrado. Reinstala Voza o configura el binario en Avanzado.")
        case .modelNotFound:
            return L.t("Whisper model not found. Download it from Voza settings.", es: "Modelo Whisper no encontrado. Descárgalo desde los ajustes de Voza.")
        case .transcriptionFailed(let msg):
            return L.t("Transcription failed: \(msg)", es: "Falló la transcripción: \(msg)")
        case .emptyResult:
            return L.t("No speech detected", es: "No se detectó voz")
        }
    }
}

/// Runs whisper.cpp (`whisper-cli`) against a WAV file. Fully local, Metal-accelerated.
final class Transcriber {
    /// Candidate locations for the whisper-cli binary, in priority order:
    /// explicit user override (`whisperBinary`) → BUNDLED static v1.9.4 with
    /// embedded Metal (D043/D050) → brew fallback paths.
    static func locateBinary() -> String? {
        let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("whisper-cli").path
        return locateBinary(candidates: [
            Config.shared.whisperBinary,
            bundled,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ].compactMap { $0 })
    }

    /// Selection rule, testable hermetically: first candidate that EXISTS as
    /// an executable file wins; none → nil (transcription fails with the
    /// honest install error).
    static func locateBinary(candidates: [String]) -> String? {
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    /// Blocking transcription; call from a background queue.
    /// `initialPrompt` (learned vocabulary) biases decoding toward the user's
    /// real terms via whisper.cpp's `--prompt` — optional for existing callers.
    /// Pure argument construction (V02-style seam): testable without
    /// spawning whisper-cli. Flags documented inline.
    static func transcriptionArguments(modelPath: String, wavPath: String,
                                       language: String, initialPrompt: String?) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", wavPath,
            "-nt",                    // no timestamps
            "-np",                    // no prints
            "-ml", "1",               // single-line segments → clean paste
            "-sow",                    // split on word
            "-l", language,
        ]
        if let prompt = initialPrompt, !prompt.isEmpty {
            args.append(contentsOf: ["--prompt", prompt])
        }
        // D021 quality lever: beam search 5 for every language. The previous
        // greedy decode (-bs 1) was measurably worse than competitors' output;
        // -bs 5 is whisper.cpp's recommended accuracy/latency balance.
        args.append(contentsOf: ["-bs", "5"])
        return args
    }

    func transcribe(wavURL: URL, modelPath: String, language: String, initialPrompt: String? = nil) throws -> String {
        guard let binary = Self.locateBinary() else { throw TranscriptionError.binaryNotFound }
        guard FileManager.default.fileExists(atPath: modelPath) else { throw TranscriptionError.modelNotFound }

        let args = [binary] + Self.transcriptionArguments(modelPath: modelPath,
                                                          wavPath: wavURL.path,
                                                          language: language,
                                                          initialPrompt: initialPrompt)

        let result = try runProcess(launchPath: args[0], arguments: Array(args.dropFirst()), timeout: Config.transcriptionTimeoutSeconds)
        guard result.exitCode == 0 else {
            throw TranscriptionError.transcriptionFailed(result.stderr.suffix(400).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let text = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // whisper emits non-speech markers ([BLANK_AUDIO], (wind blowing), …) for
        // silence/noise. Dictating silence must not paste a hallucinated marker:
        // treat an output that is ONLY a marker as empty (caught during smoke:
        // a 0.6 s silent recording transcribed as "[BLANK_AUDIO]").
        if Self.isNonSpeechMarker(text) { throw TranscriptionError.emptyResult }
        guard !text.isEmpty else { throw TranscriptionError.emptyResult }
        return text
    }

    static func isNonSpeechMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count <= 40 else { return false } // real dictation is never this short with brackets
        let lowered = t.lowercased()
        if lowered.hasPrefix("[") && lowered.hasSuffix("]") { return true }
        if lowered.hasPrefix("(") && lowered.hasSuffix(")") { return true }
        return false
    }

    private func runProcess(launchPath: String, arguments: [String], timeout: TimeInterval) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        // D050 (F-05 fix): drain stdout and stderr concurrently while the child
        // runs so a >64 KB output never fills the kernel pipe buffer and deadlocks.
        var outData = Data()
        var errData = Data()
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            drainGroup.wait()
            throw TranscriptionError.transcriptionFailed("timeout")
        }
        drainGroup.wait()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err, process.terminationStatus)
    }
}
