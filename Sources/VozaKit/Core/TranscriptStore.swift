import Foundation

/// P1-6 (audit 2026-09-21): fixed-format stamps are a FILE FORMAT, not a
/// user-facing label. Without en_US_POSIX, a 12-hour locale (AM/PM) or a
/// non-gregorian calendar (Buddist year 2569) makes date(from:) fail for
/// every entry — the whole history silently vanishes after a relaunch.
/// LearningLog already does this; the store must match.
private func applyPOSIXLocale(_ f: DateFormatter) {
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = .current
}

struct TranscriptEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let text: String
    let cleaned: Bool

    // Cached formatters (DateFormatter construction is expensive; these run
    // per history row render / per parse).
    private static let timeLabelFormatter = makeEntryFormatter("HH:mm")
    private static let dayLabelFormatter = makeEntryFormatter("yyyy-MM-dd")
    /// Shared with `TranscriptStore.parseEntries` (same file).
    static let entryStampFormatter = makeEntryFormatter("yyyy-MM-dd HH:mm:ss")
    /// P1-6 companion: stamps WRITTEN before the POSIX fix carry the system
    /// locale of the writing machine. Parsing stays backward-compatible:
    /// POSIX first, legacy-locale second. (Writes are always POSIX now.)
    static let legacyEntryStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()
    private static func makeEntryFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        applyPOSIXLocale(f)
        return f
    }

    var timeLabel: String {
        Self.timeLabelFormatter.string(from: date)
    }
    var dayLabel: String {
        Self.dayLabelFormatter.string(from: date)
    }
}

/// In-memory ring of recent transcripts + append-only markdown log at ~/Dictation/YYYY-MM.md.
final class TranscriptStore {
    static let shared = TranscriptStore()

    private(set) var recent: [TranscriptEntry] = []
    private let queue = DispatchQueue(label: "voza.transcriptstore")
    private let paths: AppPaths
    private let clock: Clock

    /// Injected dependencies (plan-glm V01). Defaults reproduce the exact
    /// baseline production behavior; tests inject QA paths and a fixed clock.
    init(paths: AppPaths = .default, clock: Clock = SystemClock()) {
        self.paths = paths
        self.clock = clock
    }

    /// History directory for the CURRENT store instance. Never creates
    /// directories (moved to `appendToFile`'s prepare step, V01-AC01).
    /// Legacy static form (pre-V01 callers): resolves baseline paths read-only.
    static var logDirectory: URL { AppPaths.default.history }
    var logDirectory: URL { paths.history }

    func add(text: String, cleaned: Bool) {
        let entry = TranscriptEntry(id: UUID(), date: clock.now, text: text, cleaned: cleaned)
        // P1-1 (audit 2026-09-21): the in-memory insert used to live in a
        // main.async NESTED after the disk write — a caller refreshing right
        // after `add` (DictationPipeline → AppState.refresh) read a STALE
        // list and the just-made dictation was missing from History until
        // the popover was reopened. Insert FIRST, synchronously on main (all
        // mutations of `recent` happen on main), then persist to disk.
        if Thread.isMainThread {
            insertRecent(entry)
        } else {
            DispatchQueue.main.async { self.insertRecent(entry) }
        }
        queue.async { [weak self] in
            self?.appendToFile(entry)
        }
    }

    private func insertRecent(_ entry: TranscriptEntry) {
        recent.insert(entry, at: 0)
        if recent.count > 50 {
            recent.removeLast()
        }
    }

    /// Test seam (V01 hermeticity): drains pending disk operations so a QA
    /// store never writes AFTER its TestEnvironment was torn down (the QA
    /// root would be recreated and flagged as survived-teardown).
    func drainPendingWritesForTests() {
        queue.sync { }
    }

    /// Pure markdown parser — testable without touching the user's log files.
    /// FIX (audit v2 §3.9): the ✨ marker is stripped BEFORE parsing the timestamp.
    /// Previously `DateFormatter.date(from:)` received "…  ✨" and failed, so every
    /// cleaned entry silently vanished from the history after a relaunch.
    static func parseEntries(fromMarkdown raw: String) -> [TranscriptEntry] {
        let tf = TranscriptEntry.entryStampFormatter
        var entries: [TranscriptEntry] = []
        for chunk in raw.components(separatedBy: "\n## ") {
            let body = chunk.hasPrefix("## ") ? String(chunk.dropFirst(3)) : chunk
            guard let nl = body.firstIndex(of: "\n") else { continue }
            let stamp = String(body[..<nl]).trimmingCharacters(in: .whitespaces)
            let cleaned = stamp.contains("✨")
            let cleanStamp = stamp
                .replacingOccurrences(of: "✨", with: "")
                .trimmingCharacters(in: .whitespaces)
            let text = body[body.index(after: nl)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = tf.date(from: cleanStamp) ?? TranscriptEntry.legacyEntryStampFormatter.date(from: cleanStamp)
            guard let date, !text.isEmpty else { continue }
            entries.append(TranscriptEntry(id: UUID(), date: date, text: text, cleaned: cleaned))
        }
        return entries
    }

    private func appendToFile(_ entry: TranscriptEntry) {
        // Write path: prepare the history tree right before appending (V01-AC01).
        guard paths.prepareHistory() else { return }
        let monthFile = paths.history.appendingPathComponent("\(Self.monthFormatter.string(from: entry.date)).md")
        let block = "## \(Self.stampFormatter.string(from: entry.date))\(entry.cleaned ? "  ✨" : "")\n\n\(entry.text)\n\n"
        if !FileManager.default.fileExists(atPath: monthFile.path) {
            let header = "# Dictation log — \(Self.monthFormatter.string(from: entry.date))\n\n"
            try? header.write(to: monthFile, atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: monthFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(block.utf8))
        }
    }

    /// Hydrate recent entries from the markdown logs (current + previous month).
    func loadRecent(limit: Int = 10) {
        queue.async { [weak self] in
            var files: [URL] = []
            for offset in [0, -1] {
                let date = Calendar.current.date(byAdding: .month, value: offset, to: Date()) ?? Date()
                let url = self?.paths.history.appendingPathComponent("\(Self.monthFormatter.string(from: date)).md")
                if let url, FileManager.default.fileExists(atPath: url.path) { files.append(url) }
            }
            var entries: [TranscriptEntry] = []
            for url in files {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                entries.append(contentsOf: Self.parseEntries(fromMarkdown: raw))
            }
            entries.sort { $0.date > $1.date }
            DispatchQueue.main.async {
                self?.recent = Array(entries.prefix(limit))
            }
        }
    }

    // Cached formatters for the serial I/O queue ( DateFormatter allocation
    // per append was pure churn). parseEntries keeps a local formatter so it
    // stays safe when called concurrently from arbitrary threads.
    private static let monthFormatter: DateFormatter = makeFormatter("yyyy-MM")
    private static let stampFormatter: DateFormatter = makeFormatter("yyyy-MM-dd HH:mm:ss")
    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        applyPOSIXLocale(f)
        return f
    }

}
