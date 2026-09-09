import Foundation
@testable import VozaKit

/// Hermetic QA environment for tests (plan-glm V01).
///
/// Owns a UNIQUE temporary root, an isolated volatile defaults suite and a
/// fixed clock. Isolation comes from injected dependencies — never from
/// repurposing HOME, CODEX_HOME or any global environment variable (QA.md §1).
///
/// Teardown removes ONLY what this environment owns: its root tree and its
/// defaults suite. Anything the test creates outside the root (e.g. the
/// sibling sentinel file used to verify teardown scope) survives untouched
/// (V01-AC03).
final class TestEnvironment {
    /// Unique root for this run: every environment is isolated from every
    /// other, including concurrent test runs on the same machine.
    let root: URL
    /// AppPaths confined to `root`.
    let paths: AppPaths
    /// Volatile, isolated defaults: no key is ever read from or written to
    /// the user's real preference domain.
    let defaults: UserDefaults
    /// Deterministic clock. Tests advance it explicitly (`env.clock.advance(...)`,
    /// reference semantics) — nothing sleeps.
    let clock: FixedClock

    private let suiteName: String
    private var tornDown = false

    /// Creates the environment. The root is NOT created on disk: components
    /// under test must not depend on eager creation (V01-AC01).
    init() throws {
        suiteName = "voza.tests." + UUID().uuidString
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths.qa(root: root)
        defaults = try UserDefaults(suiteName: suiteName).unwrapOrThrow(
            TestEnvironmentError.defaultsUnavailable(suiteName)
        )
        clock = FixedClock(wall: Date(timeIntervalSince1970: 1_700_000_000))
    }

    deinit {
        assert(tornDown, "TestEnvironment leaked: call tearDown() in the test that owns it")
        if !tornDown { tearDown() }
    }

    /// Removes ONLY this environment's resources: the root tree and the
    /// defaults suite. Fails the test if anything it did not create is
    /// discovered inside its root (contamination detector).
    func tearDown(file: StaticString = #filePath, line: UInt = #line) {
        guard !tornDown else { return }
        tornDown = true

        defaults.removePersistentDomain(forName: suiteName)

        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            // Contamination guard: the QA root must contain ONLY QA layout.
            let foreign = (try? fm.contentsOfDirectory(atPath: root.path))?
                .filter { !["AppSupport", "Dictation", "tmp"].contains($0) } ?? []
            XCTAssertTrue(foreign.isEmpty,
                          "foreign entries leaked into QA root: \(foreign)",
                          file: file, line: line)
            try? fm.removeItem(at: root)
        }
        XCTAssertTrue(!fm.fileExists(atPath: root.path),
                      "QA root survived teardown", file: file, line: line)
    }
}

enum TestEnvironmentError: Error, CustomStringConvertible {
    case defaultsUnavailable(String)

    var description: String {
        switch self {
        case .defaultsUnavailable(let suite): return "UserDefaults suite unavailable: \(suite)"
        }
    }
}

private extension Optional where Wrapped == UserDefaults {
    func unwrapOrThrow(_ error: Error) throws -> UserDefaults {
        guard let self else { throw error }
        return self
    }
}
