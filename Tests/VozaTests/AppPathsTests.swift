import XCTest
@testable import VozaKit

/// V01-AC01/AC04: AppPaths is a pure value — construction performs zero
/// filesystem side effects, and the production default is byte-for-byte the
/// baseline layout.
final class AppPathsTests: XCTestCase {
    func testConstructionCreatesNothingOnDisk() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-pathtests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        // AppPaths.qa MUST NOT create the root (or anything else).
        let paths = AppPaths.qa(root: parent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path),
                       "AppPaths construction created directories")
        XCTAssertEqual(paths.configFile.path, parent.appendingPathComponent("AppSupport/config.toml").path)
    }

    func testDefaultLayoutMatchesBaseline() {
        // V01-AC04: production defaults are unchanged — no migration, no
        // policy change. ~/.config/voza for config, ~/Dictation for history.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let p = AppPaths.default
        XCTAssertEqual(p.appSupport.path, home.appendingPathComponent(".config/voza").path)
        XCTAssertEqual(p.history.path, home.appendingPathComponent("Dictation").path)
        XCTAssertEqual(p.models.path, home.appendingPathComponent(".config/voza/models").path)
    }

    func testPrepareCreatesOnlyItsOwnTree() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        XCTAssertTrue(env.paths.prepareAppSupport())
        XCTAssertTrue(env.paths.prepareHistory())
        let entries = try FileManager.default.contentsOfDirectory(atPath: env.root.path).sorted()
        XCTAssertEqual(entries, ["AppSupport", "Dictation"], "prepare created more than its own tree")
        // Reads still never create: re-preparing is idempotent and nothing new appears.
        XCTAssertTrue(env.paths.prepareAppSupport())
    }
}
