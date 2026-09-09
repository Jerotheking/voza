import Foundation

/// All filesystem locations Voza touches, resolved from one injected value
/// (plan-glm V01). Components never touch `FileManager` default locations
/// directly: tests inject `.qa(root:)` so nothing outside the QA root is
/// read or written.
///
/// Directory creation is NOT a side effect of construction or reading
/// (V01-AC01). Call `prepareAppSupport()` / `prepareHistory()` from write
/// paths only, right before persisting.
struct AppPaths: Sendable, Equatable {
    /// Root for config.toml, .env, perf.json, license.json and models.
    let appSupport: URL
    /// Directory of the append-only dictation history (~/Dictation by default).
    let history: URL
    /// Scratch space for session WAVs and download `.part` files.
    let temp: URL

    /// Baseline production layout. Does NOT create anything on disk.
    /// Byte-for-byte identical to the pre-V01 hardcoded defaults (V01-AC04):
    /// config under ~/.config/voza, history at ~/Dictation, temp in the
    /// system temporary directory.
    static var `default`: AppPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppPaths(
            appSupport: home.appendingPathComponent(".config/voza", isDirectory: true),
            history: home.appendingPathComponent("Dictation", isDirectory: true),
            temp: FileManager.default.temporaryDirectory
        )
    }

    /// QA layout: everything under one root that a test owns and deletes.
    static func qa(root: URL) -> AppPaths {
        AppPaths(
            appSupport: root.appendingPathComponent("AppSupport", isDirectory: true),
            history: root.appendingPathComponent("Dictation", isDirectory: true),
            temp: root.appendingPathComponent("tmp", isDirectory: true)
        )
    }

    // MARK: - File locations

    var configFile: URL { appSupport.appendingPathComponent("config.toml") }
    var envFile: URL { appSupport.appendingPathComponent(".env") }
    var perfFile: URL { appSupport.appendingPathComponent("perf.json") }
    var licenseCacheFile: URL { appSupport.appendingPathComponent("license.json") }
    var models: URL { appSupport.appendingPathComponent("models", isDirectory: true) }

    // MARK: - Lazy preparation (write paths only)

    /// Creates the app-support tree. Returns false when creation failed so
    /// callers can surface the error; never called from getters/reads.
    @discardableResult
    func prepareAppSupport() -> Bool {
        (try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)) != nil
    }

    /// Creates the history directory. Call right before appending history.
    @discardableResult
    func prepareHistory() -> Bool {
        (try? FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)) != nil
    }
}
