import XCTest
@testable import VozaKit

final class ConfigTests: XCTestCase {
    func testCatalogHashesAreValidFormat() {
        for model in WhisperCatalog.all {
            XCTAssertEqual(model.sha256.count, 64, "bad hash for \(model.id)")
            XCTAssertTrue(model.sha256.allSatisfy { $0.isHexDigit }, "bad hash for \(model.id)")
            XCTAssertTrue(model.bytes > 1_000_000, "suspicious size for \(model.id)")
        }
    }

    func testHardwareProfileRecommendsByRAM() {
        let ram = HardwareProfile.totalRAMGB
        let rec = HardwareProfile.recommendedModel()
        if ram >= 30 {
            XCTAssertEqual(rec, "large-v3-turbo")
        } else if ram >= 14 {
            XCTAssertEqual(rec, "small.en-q5_1")
        } else {
            XCTAssertEqual(rec, "small.en-q5_1")
        }
    }

    func testLocalizerPicksLanguage() {
        let original = L.override
        defer { L.override = original }
        L.override = "es"
        XCTAssertTrue(L.isSpanish)
        XCTAssertEqual(L.t("Hello", es: "Hola"), "Hola")
        L.override = "en"
        XCTAssertFalse(L.isSpanish)
        XCTAssertEqual(L.t("Hello", es: "Hola"), "Hello")
    }

    func testTranscriptStoreWritesAndReadsLog() {
        let store = TranscriptStore.shared
        let marker = "voza-test-\(UUID().uuidString.prefix(6))"
        let exp = expectation(description: "log written")
        store.add(text: marker, cleaned: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let file = TranscriptStore.logDirectory.appendingPathComponent("\(f.string(from: Date())).md")
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        XCTAssertTrue(content.contains(marker), "marker not found in log file")
    }
}
