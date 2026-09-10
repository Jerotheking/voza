import CryptoKit
import Foundation

struct WhisperModel: Identifiable, Hashable, Sendable {
    let id: String          // e.g. "small.en"
    let file: String        // ggml file name
    let bytes: Int
    let sha256: String
    var displayName: String { id }
    var isEnglishOnly: Bool { id.hasSuffix(".en") }
    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum WhisperCatalog {
    /// Size + SHA-256 fetched from the HuggingFace API for ggerganov/whisper.cpp (2026-09).
    static let all: [WhisperModel] = [
        WhisperModel(id: "tiny.en",   file: "ggml-tiny.en.bin",   bytes: 77_704_715,   sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"),
        WhisperModel(id: "base.en",   file: "ggml-base.en.bin",   bytes: 147_964_211,  sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"),
        WhisperModel(id: "small.en-q5_1", file: "ggml-small.en-q5_1.bin", bytes: 190_098_681, sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30"),
        // Multilingual twin at ~the same size — the correct default for "es"/"auto"
        // (P0 fix from external audit v2, §3.2: English-only must never be recommended
        // for non-English or auto language).
        WhisperModel(id: "small-q5_1", file: "ggml-small-q5_1.bin", bytes: 190_085_487, sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"),
        WhisperModel(id: "small.en",  file: "ggml-small.en.bin",  bytes: 487_614_201,  sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"),
        WhisperModel(id: "small",     file: "ggml-small.bin",     bytes: 487_601_967,  sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"),
        WhisperModel(id: "medium",    file: "ggml-medium.bin",    bytes: 1_533_763_059, sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"),
        WhisperModel(id: "large-v3-turbo", file: "ggml-large-v3-turbo.bin", bytes: 1_624_555_275, sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
    ]
    static func byId(_ id: String) -> WhisperModel? { all.first { $0.id == id } }
}

/// Hardware profile → recommended model. Runs automatically; user can override in Settings.
enum HardwareProfile {
    static var totalRAMGB: Int {
        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
        return Int(size / 1_073_741_824)
    }

    static var machineLabel: String {
        var brand = [CChar](repeating: 0, count: 128)
        var sizeLen = brand.count
        sysctlbyname("machdep.cpu.brand_string", &brand, &sizeLen, nil, 0)
        return String(cString: brand)
    }

    /// - Parameter language: resolved speech language ("auto", "en", "es", ...).
    ///   "en" may get the English-only build (slightly better on English);
    ///   everything else — including "auto" — must get a multilingual model.
    ///
    /// V02: pure tier policy over an injected RAM tier. `tier` is "16+" | "8"
    /// | "low" (inverted range so tests can assert every branch without
    /// constructing fictitious RAMs). The production wrapper reads the real
    /// machine; tests inject the tier — no `totalRAMGB` mutation, ever.
    static func recommendedModel(language: String, tier: RAMTier) -> String {
        switch tier {
        case .highRAM:   return "large-v3-turbo"
        case .midRAM:    return language == "en" ? "small.en" : "small"
        case .lowRAM:    return language == "en" ? "small.en-q5_1" : "small-q5_1"
        }
    }

    /// RAM tiers (V02): explicit cases instead of scattered thresholds.
    enum RAMTier {
        case highRAM   // ≥ 16 GB — large-v3-turbo fits comfortably (Metal ~1–1.5 GB)
        case midRAM    // 8..<16 GB — fp16 small (better than q5_1)
        case lowRAM    // < 8 GB — quantized builds only

        static func tier(forRAMGB ram: Int) -> RAMTier {
            switch ram {
            case 16...: return .highRAM
            case 8..<16: return .midRAM
            default: return .lowRAM
            }
        }
    }

    /// Production wrapper: reads the real machine's RAM, then delegates to the
    /// pure policy. Callers unchanged.
    static func recommendedModel(language: String) -> String {
        recommendedModel(language: language, tier: RAMTier.tier(forRAMGB: totalRAMGB))
    }
}

/// Downloads models from HuggingFace with SHA-256 verification and resume support.
final class ModelManager: Sendable {
    static let shared = ModelManager()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 3600
        session = URLSession(configuration: cfg)
    }

    var modelsDirectory: URL {
        let url = URL(fileURLWithPath: Config.shared.resolvedModelsDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func localPath(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.file)
    }

    func fileSize(at url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return nil }
        return size
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        fileSize(at: localPath(for: model)) == model.bytes
    }

    func downloadedModels() -> [WhisperModel] {
        WhisperCatalog.all.filter { isDownloaded($0) }
    }

    /// Resolves the model actually used for a run — descriptor + path together, so
    /// callers can attribute RTF/metrics to the REAL model, not the configured one
    /// (P0 fix from external audit v2, §3.3: silent fallback must not poison auto-tuning).
    func resolvedModel(preferredId: String) -> (model: WhisperModel, path: String)? {
        if let m = WhisperCatalog.byId(preferredId), isDownloaded(m) {
            return (m, localPath(for: m).path)
        }
        return downloadedModels().first.map { ($0, localPath(for: $0).path) }
    }

    func resolvedModelPath(preferredId: String) -> String? {
        resolvedModel(preferredId: preferredId)?.path
    }

    /// Async download with progress callback (0...1). Verifies size + SHA-256 before success.
    /// `directory` overrides the destination (V02): the smoke e2e mode MUST pass a
    /// QA path — downloads never land in the real models dir from tests.
    func download(_ model: WhisperModel,
                  into directory: String? = nil,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let dest: URL
        if let directory {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            dest = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(model.file)
        } else {
            dest = localPath(for: model)
        }
        let partial = dest.appendingPathExtension("part")
        let fm = FileManager.default
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(model.file)")!

        var resumeFrom: Int64 = 0
        if let existing = fileSize(at: partial), existing > 0 { resumeFrom = Int64(existing) }

        var request = URLRequest(url: url)
        if resumeFrom > 0 {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("bad response")
        }
        switch http.statusCode {
        case 200:
            resumeFrom = 0
            fm.createFile(atPath: partial.path, contents: nil) // truncate
        case 206:
            break // appending to existing partial
        case 416:
            // Range beyond EOF: the partial is complete → fall through to verification.
            // If it is NOT complete, the partial is corrupt/invalid → delete and restart clean.
            if fileSize(at: partial) != model.bytes {
                try? fm.removeItem(at: partial)
                resumeFrom = 0
                fm.createFile(atPath: partial.path, contents: nil)
            }
        default:
            throw TranscriptionError.transcriptionFailed("HTTP \(http.statusCode)")
        }
        if !fm.fileExists(atPath: partial.path) {
            fm.createFile(atPath: partial.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()

        let total = Int64(model.bytes)
        var received = resumeFrom
        var buffer = Data()
        buffer.reserveCapacity(1 << 18)

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 18 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    progress(min(Double(received) / Double(total), 1.0))
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        } catch {
            // FIX (audit v2 §3.10): a network drop must NOT destroy download progress.
            // Keep the .part file on recoverable network errors so the next attempt
            // resumes; delete only for non-recoverable errors (disk write failure).
            if !(error is URLError) {
                try? fm.removeItem(at: partial)
            }
            throw error
        }

        guard received == total, fileSize(at: partial) == model.bytes else {
            // Truncated stream (often a silent network drop): keep the partial so
            // the next attempt resumes from here instead of starting over.
            throw TranscriptionError.transcriptionFailed("size mismatch: got \(received), expected \(model.bytes)")
        }
        progress(1.0)

        let digest = try Self.sha256(of: partial)
        guard digest == model.sha256 else {
            try? fm.removeItem(at: partial)
            throw TranscriptionError.transcriptionFailed("SHA-256 mismatch")
        }

        try? fm.removeItem(at: dest)
        try fm.moveItem(at: partial, to: dest)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
