import XCTest
@testable import VozaKit

/// FirstRunExperience one-shot flag — hermetic via a volatile defaults suite
/// (same isolation pattern as the localizer tests): the real user preference
/// domain is never touched from a test process.
final class FirstRunExperienceTests: XCTestCase {
    func testPendingByDefaultAndConsumedOnce() {
        let suiteName = "voza.tests.firstrun." + UUID().uuidString
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("volatile defaults suite unavailable")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }

        FirstRunExperience.defaultsSuite = suite
        defer { FirstRunExperience.defaultsSuite = nil }

        // Fresh install: the moment is pending.
        XCTAssertTrue(FirstRunExperience.firstDictationPending)

        // Consuming it flips the flag and it never comes back.
        FirstRunExperience.markFirstDictationShown()
        XCTAssertFalse(FirstRunExperience.firstDictationPending)

        // Idempotent: repeat consumption cannot resurrect the moment.
        FirstRunExperience.markFirstDictationShown()
        XCTAssertFalse(FirstRunExperience.firstDictationPending)
    }

    func testSuitesAreIndependent() {
        // A second suite behaves as a fresh install — proves the seam isolates
        // per-suite state (no hidden singleton leakage between environments).
        let nameA = "voza.tests.firstrun." + UUID().uuidString
        let nameB = "voza.tests.firstrun." + UUID().uuidString
        guard let a = UserDefaults(suiteName: nameA), let b = UserDefaults(suiteName: nameB) else {
            return XCTFail("volatile defaults suites unavailable")
        }
        defer {
            a.removePersistentDomain(forName: nameA)
            b.removePersistentDomain(forName: nameB)
        }

        FirstRunExperience.defaultsSuite = a
        FirstRunExperience.markFirstDictationShown()
        XCTAssertFalse(FirstRunExperience.firstDictationPending)

        FirstRunExperience.defaultsSuite = b
        XCTAssertTrue(FirstRunExperience.firstDictationPending,
                      "a separate suite must behave as a fresh install")

        FirstRunExperience.defaultsSuite = nil
    }
}
