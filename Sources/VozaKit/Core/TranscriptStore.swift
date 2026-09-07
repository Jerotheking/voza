import Foundation

struct TranscriptEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let text: String
    let cleaned: Bool

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// In-memory ring of recent transcripts + append-only markdown log at ~/Dictation/YYYY-MM.md.
final class TranscriptStore {
    static let shared = TranscriptStore()

    private(set) var recent: [TranscriptEntry] = []
    private let queue = DispatchQueue(label: "voza.transcriptstore")
    static var logDirectory: URL {
        let url = URL(fileURLWithPath: Config.shared.resolvedLogDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func add(text: String, cleaned: Bool) {
        let entry = TranscriptEntry(id: UUID(), date: Date(), text: text, cleaned: cleaned)
        queue.async { [weak self] in
            self?.appendToFile(entry)
            DispatchQueue.main.async {
                self?.recent.insert(entry, at: 0)
                if self?.recent.count ?? 0 > 50 {
                    self?.recent.removeLast()
                }
            }
        }
    }

    private func appendToFile(_ entry: TranscriptEntry) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let monthFile = Self.logDirectory.appendingPathComponent("\(f.string(from: entry.date)).md")
        let tf = DateFormatter()
        tf.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let block = "## \(tf.string(from: entry.date))\(entry.cleaned ? "  ✨" : "")\n\n\(entry.text)\n\n"
        if !FileManager.default.fileExists(atPath: monthFile.path) {
            let header = "# Dictation log — \(f.string(from: entry.date))\n\n"
            try? header.write(to: monthFile, atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: monthFile) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(block.utf8))
        }
    }

    /// Hydrate recent entries from the markdown logs (current + previous month).
    func loadRecent(limit: Int = 10) {
        queue.async { [weak self] in
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            var files: [URL] = []
            for offset in [0, -1] {
                let date = Calendar.current.date(byAdding: .month, value: offset, to: Date()) ?? Date()
                let url = Self.logDirectory.appendingPathComponent("\(f.string(from: date)).md")
                if FileManager.default.fileExists(atPath: url.path) { files.append(url) }
            }
            var entries: [TranscriptEntry] = []
            for url in files {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let tf = DateFormatter()
                tf.dateFormat = "yyyy-MM-dd HH:mm:ss"
                for chunk in raw.components(separatedBy: "\n## ") {
                    let body = chunk.hasPrefix("## ") ? String(chunk.dropFirst(3)) : chunk
                    guard let nl = body.firstIndex(of: "\n") else { continue }
                    let stamp = String(body[..<nl]).trimmingCharacters(in: .whitespaces)
                    let text = body[body.index(after: nl)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let date = tf.date(from: stamp), !text.isEmpty else { continue }
                    entries.append(TranscriptEntry(id: UUID(), date: date, text: text, cleaned: stamp.contains("✨")))
                }
            }
            entries.sort { $0.date > $1.date }
            DispatchQueue.main.async {
                self?.recent = Array(entries.prefix(limit))
            }
        }
    }
}
