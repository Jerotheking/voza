import Foundation

/// Structured log for the auto-learn pipeline (D034): one append-only line
/// per event, so "why didn't it learn?" is answerable from disk instead of by
/// archaeology (the Sintelia case was invisible — nothing recorded that the
/// session even started). Mirror of the D030 CleanupLog design: writes never
/// block the watch loop, never fail the dictation, rotate at 1 MB, and the
/// sink is injectable for hermetic tests.
///
/// Location: ~/Library/Logs/voza/learning.log (app logs, not user data —
/// content is the learned pairs themselves, which stay on this Mac anyway).
final class LearningLog {
    static let shared = LearningLog()

    enum Event {
        /// A paste started a learning session.
        case start(hasElement: Bool)
        /// A lesson was recorded.
        case learned(heard: String, said: String)
        /// The window closed without a lesson (timeout, unreadable field, or
        /// guards rejected the edit).
        case expired
        /// The target app's AX tree never appeared even after forced overrides
        /// (Electron that ignores AXManualAccessibility) — a distinct failure
        /// mode from "no edit made". accepted/unsupported counts tell WHICH
        /// refusal mode the app used.
        case axNeverWoke(accepted: Int, unsupported: Int)
    }

    private let lock = NSLock()
    private let clock: Clock
    private let directory: URL
    private let maxBytes = 1_000_000
    /// Test seam.
    var sink: ((String) -> Void)?
    /// Global mute for test processes (D034: watcher functions log to the
    /// shared instance even under a QASink — without this, `swift test` runs
    /// wrote fake "learned" lines into the USER's real bitácora).
    nonisolated(unsafe) static var isMutedForTests = false

    init(clock: Clock = SystemClock(), directory: URL? = nil) {
        self.clock = clock
        self.directory = directory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/voza", isDirectory: true)
    }

    func event(_ e: Event) {
        if Self.isMutedForTests { return }
        let ts = Self.timestamp(clock.now)
        let line: String
        switch e {
        case .start(let hasElement):
            line = "\(ts) | start | ax=\(hasElement ? "live" : "late-baseline")"
        case .learned(let heard, let said):
            let h = heard.count > 60 ? String(heard.prefix(60)) + "…" : heard
            let s = said.count > 60 ? String(said.prefix(60)) + "…" : said
            line = "\(ts) | learned | \(h) -> \(s)"
        case .expired:
            line = "\(ts) | expired | no stable approved edit in window"
        case .axNeverWoke(let accepted, let unsupported):
            line = "\(ts) | expired | ax-never-woke (overrides accepted=\(accepted) unsupported=\(unsupported))"
        }
        lock.lock()
        defer { lock.unlock() }
        if let sink {
            sink(line)
            return
        }
        append(line: line)
    }

    private func append(line: String) {
        let fm = FileManager.default
        let file = directory.appendingPathComponent("learning.log")
        if let data = try? Data(contentsOf: file), data.count > maxBytes {
            try? fm.removeItem(at: file)
        }
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file)
            }
        }
    }

    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX") // logs: never locale-dependent
        f.timeZone = .current
        return f.string(from: date)
    }
}
