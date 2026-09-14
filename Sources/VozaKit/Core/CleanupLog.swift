import Foundation

/// D029 — structured diagnostics for the cleanup pipeline.
///
/// The 2026-09-14 incidents (3-minute stuck polish, tripwire fallbacks) were
/// only diagnosable by `sample`-ing the live process because the engine's
/// `print` output goes to stdout, which a launched .app discards. Every
/// cleanup decision now lands here as one append-only line, e.g.:
///
///     2026-09-14T21:33:05Z | mlx      | ok       | 2.14s | tokens=87
///     2026-09-14T21:35:10Z | mlx      | tripwall | 15.02s | tokens=61 | fallback=raw
///
/// Writes never throw and never block the audio path: failures to write are
/// swallowed by contract (diagnostics must not be able to break dictation).
/// The file rotates at 1 MB (cleanup.log → cleanup.old) so it cannot grow
/// unbounded. `directory` is injectable so tests stay hermetic (QA.md §1).
public enum CleanupLog {

    /// Rotated-size ceiling for the active log.
    static let maxBytes = 1_000_000

    /// Resolves the real destination. Kept as a function (not a stored
    /// global) so nothing but the caller's explicit override can redirect it.
    static func defaultDirectory() -> URL? {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("voza", isDirectory: true)
    }

    /// ISO-8601 UTC timestamp — one line, sortable, locale-independent.
    static func timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Appends one event line. Thread-safe: dictation cleanup runs on a
    /// detached task while Settings/tests may log concurrently.
    public static func write(_ provider: String, _ event: String,
                             seconds: Double? = nil, detail: String? = nil,
                             directory: URL? = nil) {
        let dir = directory ?? defaultDirectory()
        guard let dir else { return }
        var parts = [timestamp(), provider.padding(toLength: 9, withPad: " ", startingAt: 0), event]
        if let s = seconds { parts.append(String(format: "%.2fs", s)) }
        if let d = detail, !d.isEmpty { parts.append(d) }
        let line = parts.joined(separator: " | ") + "\n"

        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("cleanup.log")
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int,
               size > maxBytes {
                let old = dir.appendingPathComponent("cleanup.old")
                if FileManager.default.fileExists(atPath: old.path) {
                    try? FileManager.default.removeItem(at: old)
                }
                try? FileManager.default.moveItem(at: file, to: old)
            }
            if let handle = FileHandle(forWritingAtPath: file.path) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: file)
            }
        } catch {
            // Swallowed by contract — see docstring.
        }
    }

    private static let lock = NSLock()
}
