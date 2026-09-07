import Foundation

/// In-app bootstrap for the whisper.cpp engine via Homebrew, with streamed output.
private let knownBrewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

@MainActor
final class BrewInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var logLines: [String] = []
    @Published var installError: String?
    @Published var installSucceeded = false

    nonisolated static func brewPath() -> String? {
        knownBrewPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// Streams `brew install whisper-cpp` line-by-line into `logLines`.
    func installEngine() {
        guard !isInstalling else { return }
        guard let brew = Self.brewPath() else {
            installError = L.t("Homebrew not found", es: "Homebrew no encontrado")
            return
        }
        isInstalling = true
        logLines = [L.t("Running: brew install whisper-cpp", es: "Ejecutando: brew install whisper-cpp")]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "whisper-cpp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.logLines.append(trimmed)
                if self?.logLines.count ?? 0 > 200 { self?.logLines.removeFirst(100) }
            }
        }

        do {
            try process.run()
        } catch {
            isInstalling = false
            installError = error.localizedDescription
            return
        }

        Task.detached { [weak self] in
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let success = process.terminationStatus == 0
            await MainActor.run { [weak self] in
                self?.isInstalling = false
                if success {
                    self?.installSucceeded = true
                    self?.logLines.append(L.t("Engine installed ✓", es: "Motor instalado ✓"))
                } else {
                    self?.installError = L.t("brew exited with code \(process.terminationStatus)", es: "brew terminó con código \(process.terminationStatus)")
                }
            }
        }
    }
}
