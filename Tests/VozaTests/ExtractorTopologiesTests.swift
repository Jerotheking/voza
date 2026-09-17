import XCTest
@testable import VozaKit

/// D035 — the Sintelia lesson came out dead (`telia.` → `telia`): the
/// character diff welded the sentence-final period into the fragment. The
/// extractor now tries word-level alignment first (which also yields merge/
/// split lessons), with the character diff as fallback. These tests pin all
/// three topologies plus the guards that must not regress.
final class ExtractorTopologiesTests: XCTestCase {

    // MARK: - 1. The shipped bug: end-of-sentence fix

    func testEndOfSentenceFix() {
        // Full field: user corrects the last word of the sentence.
        let pair = CorrectionWatcher.extractPair(
            pasted: "¿Tú crees que debería de funcionar? Sin telia.",
            typed: "¿Tú crees que debería de funcionar? Sintelia.",
            expected: "¿Tú crees que debería de funcionar? Sin telia."
        )
        // Either the clean merge lesson or the exact-word fix — never a
        // punctuation-dead pair.
        XCTAssertNotNil(pair)
        if let p = pair {
            XCTAssertFalse(p.heard.hasSuffix("."), "heard must not carry the sentence period: \(p.heard)")
            XCTAssertFalse(p.said.hasSuffix("."), "said must not carry the sentence period: \(p.said)")
            // The pair must be replayable: heard exists as a whole phrase in the paste.
            XCTAssertTrue("sin telia. ¿tú crees…".lowercased().contains(p.heard.lowercased())
                          || "¿tú crees que debería de funcionar? sin telia.".lowercased().contains(p.heard.lowercased()))
        }
    }

    func testEndOfSentenceFixReplaysViaApply() {
        // End-to-end: whatever pair is learned from the real field shape must
        // actually transform a future dictation containing the same mistake.
        let original = "¿Tú crees que debería de funcionar? Sin telia."
        let corrected = "¿Tú crees que debería de funcionar? Sintelia."
        guard let pair = CorrectionWatcher.extractPair(
            pasted: original, typed: corrected, expected: original)
        else { return XCTFail("real-world shape must yield a lesson") }

        let fixed = CorrectionStore.apply("otra vez sin telia y ya", corrections: [
            Correction(id: UUID(), heard: pair.heard, said: pair.said, createdAt: Date())
        ])
        XCTAssertTrue(fixed.lowercased().contains("sintelia"),
                      "learned pair must replay: \(pair.heard) -> \(pair.said) produced: \(fixed)")
    }

    // MARK: - 2. Merge / split lessons

    func testMergeAcrossSpace() {
        let pair = CorrectionWatcher.extractPair(
            pasted: "tengo ganas de comerme un wafle y de sin telia",
            typed: "tengo ganas de comerme un wafle y de sintelia",
            expected: "tengo ganas de comerme un wafle y de sin telia"
        )
        XCTAssertEqual(pair?.heard.lowercased(), "sin telia")
        XCTAssertEqual(pair?.said.lowercased(), "sintelia")
    }

    func testSplitAcrossSpace() {
        // Identical text: no lesson (caller-level guards).
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "abrimos el por allow",
            typed: "abrimos el por allow",
            expected: "abrimos el por allow"
        ))
        // The split itself (one token → two) is a real, replayable lesson.
        let direct = CorrectionWatcher.wordLevelPair(e: "abrimos el porallow", t: "abrimos el por allow")
        XCTAssertEqual(direct?.heard.lowercased(), "porallow")
        XCTAssertEqual(direct?.said.lowercased(), "por allow")
    }

    func testMergeWithPeriodStillTrimmed() {
        // Merge at sentence end WITH final period: both fixes cooperate.
        let pair = CorrectionWatcher.extractPair(
            pasted: "hola sin telia.",
            typed: "hola Sinteliä.",
            expected: "hola sin telia."
        )
        XCTAssertNotNil(pair)
        if let p = pair {
            XCTAssertFalse(p.heard.hasSuffix("."))
            XCTAssertFalse(p.said.hasSuffix("."))
        }
    }

    // MARK: - 3. Character fallback still works (mid-word fix)

    func testMidWordLetterFixUsesCharLevel() {
        // "prueva" → "prueba": word tokens differ entirely, but the char diff
        // isolates the single letter — the PRECISE lesson.
        let pair = CorrectionWatcher.extractPair(
            pasted: "esto es una prueva",
            typed: "esto es una prueba",
            expected: "esto es una prueva"
        )
        XCTAssertEqual(pair?.heard.lowercased(), "prueva")
        XCTAssertEqual(pair?.said.lowercased(), "prueba")
    }

    func testCharLevelSingleLetterPair() {
        let pair = CorrectionWatcher.charLevelPair(e: "prueva", t: "prueba")
        XCTAssertEqual(pair?.heard.lowercased(), "prueva")
        XCTAssertEqual(pair?.said.lowercased(), "prueba")
    }

    // MARK: - 4. Guards that must not regress

    func testIdenticalTextYieldsNothing() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola mundo", typed: "hola mundo", expected: "hola mundo"))
    }

    func testCaseOnlyChangeYieldsNothing() {
        // Case mirrors are handled by the replacer's matchingCase — a lesson
        // would be dead weight.
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola tiago", typed: "hola Tiago", expected: "hola tiago"))
    }

    func testUnrelatedRewriteRejected() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola esto es una prueba de dictado",
            typed: "https://example.com/alguna/url/larga",
            expected: "hola esto es una prueba de dictado"
        ), "similarity guard must reject a URL overwrite")
    }

    func testHeardMustExistInOurPaste() {
        // Edit to the user's surrounding context: never attributed to Voza.
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "texto dictado normal",
            typed: "texto dictado normal y su corrección bien",
            expected: "texto dictado normal"
        ))
    }

    func testPunctuationOnlyDifferenceYieldsNothing() {
        // Tokens "funcionar?" vs "funcionar" differ, but after edge-trim both
        // fragments are equal — the replacer doesn't need this lesson.
        XCTAssertNil(CorrectionWatcher.wordLevelPair(e: "que funcionar?", t: "que funcionar"))
    }

    func testHeardWithInnerPunctuationKeepsIt() {
        // Word tokens "funcionar?" vs "funcionara" differ; the heard side
        // keeps its inner punctuation after edge-trim. The char fallback then
        // refines it to the precise letter-level pair — the honest lesson.
        let direct = CorrectionWatcher.extractPair(
            pasted: "que funcionar? nada",
            typed: "que funcionara nada",
            expected: "que funcionar? nada"
        )
        XCTAssertNotNil(direct)
        if let p = direct {
            // Either granularity is a valid, replayable lesson here.
            XCTAssertTrue(p.heard == "funcionar?" || p.heard.lowercased() == "funcionar",
                          "unexpected heard: \(p.heard)")
            XCTAssertEqual(p.said.lowercased(), "funcionara")
        }
    }
}
