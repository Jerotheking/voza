import XCTest
@testable import VozaKit

/// Adversarial matrix against the four learning touchpoints (extractPair,
/// apply, record, initialPrompt). Every case models a REAL way macOS apps and
/// the user interact with the pasted field: autocorrect, autocapitalize,
/// emoji panel offers, numeric edits, autocompletion, NBSP, pre-existing
/// field text. Anything that must not become a lesson returns nil; anything
/// that must replay does so end-to-end through CorrectionStore.apply.
final class AdversarialMatrixTests: XCTestCase {

    // MARK: - 1. Autocorrect & autocapitalize (must NOT learn)

    /// First-letter autocapitalize: replacer mirrors case anyway — dead weight.
    func testAutocapitalizeIsDeadWeight() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola mundo", typed: "Hola mundo", expected: "hola mundo"))
    }

    /// Repeated-word autocorrect is a pure deletion: not replayable as a
    /// replacement pair.
    func testRepeatedWordDeletionNotALesson() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "de de prueba", typed: "de prueba", expected: "de de prueba"))
    }

    /// Punctuation-only fix (., vs ,): trims to identity on both paths.
    func testPunctuationOnlyFixDies() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola, mundo", typed: "hola. mundo", expected: "hola, mundo"))
    }

    /// Emoji panel appending after the paste: nothing changed in OUR text.
    func testEmojiAppendedNotALesson() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "hola mundo", typed: "hola mundo 😊", expected: "hola mundo"))
    }

    /// NBSP vs space (some editors insert U+00A0): canon-equal, same tokens —
    /// a formatting difference, never a lesson.
    func testNbspVsSpaceIsFormattingOnly() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "uno\u{00A0}dos", typed: "uno dos", expected: "uno\u{00A0}dos"))
    }

    /// record-level backstop: a pure-case single-token pair must be refused
    /// even if a future extractor regression lets one through.
    func testRecordRefusesPureCaseSingleTokenPair() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        XCTAssertNil(store.record(heard: "tiago", said: "Tiago"))
        XCTAssertEqual(store.all().count, 0)
    }

    // MARK: - 2. Numbers & symbols (silent skip, never garbage)

    /// Digit-only replacements trim to sub-4-char fragments (letters anchor
    /// the trimming) and die on the min-length guards. They must fail CLOSED:
    /// nil — never a nonsense pair like "0" → "5".
    func testNumericReplacementFailsClosed() {
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "compra 10 entradas", typed: "compra 45 entradas", expected: "compra 10 entradas"))
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "precio 1200 dolares", typed: "precio 1230 dolares", expected: "precio 1200 dolares"))
        XCTAssertNil(CorrectionWatcher.extractPair(
            pasted: "cita a las 4 pm", typed: "cita a las 16 pm", expected: "cita a las 4 pm"))
    }

    /// D051 (F-09): Alphanumeric & uppercase technical tokens ("v2" → "v3",
    /// "ia" → "AI", "ese tres" → "S3") are now learned (>= 2 chars with uppercase or digit).
    func testShortAlphanumericAndAcronymLearned() {
        let vPair = CorrectionWatcher.extractPair(
            pasted: "el api v2 falla", typed: "el api v3 falla", expected: "el api v2 falla")
        XCTAssertEqual(vPair?.heard, "v2")
        XCTAssertEqual(vPair?.said, "v3")

        let aiPair = CorrectionWatcher.extractPair(
            pasted: "modelo de ia local", typed: "modelo de AI local", expected: "modelo de ia local")
        XCTAssertEqual(aiPair?.heard, "ia")
        XCTAssertEqual(aiPair?.said, "AI")
    }

    // MARK: - 3. Replacer semantics (apply must be surgical)

    /// Longest phrase wins at the same position: "san francisco" is consumed
    /// whole, not rewritten as "san" + "Paco".
    func testLongestPhraseWins() {
        let fixed = CorrectionStore.apply("vamos a san francisco hoy", corrections: [
            Correction(id: UUID(), heard: "francisco", said: "Paco", createdAt: Date()),
            Correction(id: UUID(), heard: "san francisco", said: "San Francisco", createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "vamos a San Francisco hoy", fixed)
    }

    /// Word-boundary guard: "hola" must never fire inside "holanda".
    func testPartialWordNotReplaced() {
        let fixed = CorrectionStore.apply("voy a holanda mañana", corrections: [
            Correction(id: UUID(), heard: "hola", said: "hola", createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "voy a holanda mañana", fixed)
    }

    /// Learned phrase followed by punctuation replays fine.
    func testTrailingPunctuationBoundary() {
        let fixed = CorrectionStore.apply("sin telia, ¿viste?", corrections: [
            Correction(id: UUID(), heard: "sin telia", said: "Sintelia", createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "Sintelia, ¿viste?", fixed)
    }

    /// Every occurrence is replaced, not just the first.
    func testAllOccurrencesReplaced() {
        let fixed = CorrectionStore.apply("sin telia otra vez sin telia", corrections: [
            Correction(id: UUID(), heard: "sin telia", said: "Sintelia", createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "Sintelia otra vez Sintelia", fixed)
    }

    /// ALL-CAPS heard text stays ALL-CAPS after replacement (case mirroring).
    func testCaseMirrorAllCaps() {
        let fixed = CorrectionStore.apply("SIN TELIA EN SERIO", corrections: [
            Correction(id: UUID(), heard: "sin telia", said: "Sintelia", createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "SINTELIA EN SERIO", fixed)
    }

    // MARK: - 4. Field context isolation (paste into non-empty fields)

    /// Text BEFORE the paste must not leak into the lesson.
    func testPrefixContextIsolation() {
        let pair = CorrectionWatcher.extractPair(
            pasted: "hola prueva",
            typed: "mensaje anterior. hola prueba",
            expected: "mensaje anterior. hola prueva")
        XCTAssertEqual(pair?.heard, "prueva")
        XCTAssertEqual(pair?.said, "prueba")
    }

    /// Text AFTER the paste must not be dragged into the lesson either.
    func testSuffixContextIsolation() {
        let pair = CorrectionWatcher.extractPair(
            pasted: "llamame prueva",
            typed: "llamame prueba porfa",
            expected: "llamame prueva porfa")
        XCTAssertEqual(pair?.heard, "prueva")
        XCTAssertEqual(pair?.said, "prueba")
    }

    // MARK: - 5. Realistic full-loop (extract → store → apply)

    /// Whisper mishears "agenda" as "genda" mid-sentence; the lesson must
    /// replay on a future dictation.
    func testRealisticMidSentenceFixReplays() {
        let original = "oye prepárame la agenda de mañana con la reunión de equipo y recordatorio de comprar café"
        let misheard = "oye prepárame la genda de mañana con la reunión de equipo y recordatorio de comprar café"
        guard let pair = CorrectionWatcher.extractPair(pasted: misheard, typed: original, expected: misheard)
        else { return XCTFail("mid-sentence fix must yield a lesson") }
        XCTAssertEqual(pair.heard.lowercased(), "genda")
        XCTAssertEqual(pair.said.lowercased(), "agenda")

        let fixed = CorrectionStore.apply("mi genda personal", corrections: [
            Correction(id: UUID(), heard: pair.heard, said: pair.said, createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "mi agenda personal", fixed)
    }

    /// Accented vowel fix expands to the whole word (mid-word expansion path).
    func testAccentedVowelFix() {
        let pair = CorrectionWatcher.extractPair(
            pasted: "me gusta el corazòn azul",
            typed: "me gusta el corazón azul",
            expected: "me gusta el corazòn azul")
        XCTAssertEqual(pair?.heard, "corazòn")
        XCTAssertEqual(pair?.said, "corazón")
    }

    /// The shipped Freebuff case, end to end through the store: learn, apply
    /// on a brand-new dictation with different case shape.
    func testFreebuffMergeEndToEndReplay() {
        let original = "tengo ganas de comerme un wafle y de sin telia"
        let corrected = "tengo ganas de comerme un wafle y de sintelia"
        guard let pair = CorrectionWatcher.extractPair(pasted: original, typed: corrected, expected: original)
        else { return XCTFail("merge case must yield a lesson") }
        XCTAssertEqual(pair.heard.lowercased(), "sin telia")
        XCTAssertEqual(pair.said.lowercased(), "sintelia")

        let fixed = CorrectionStore.apply("hola Sin Telia mi buen", corrections: [
            Correction(id: UUID(), heard: pair.heard, said: pair.said, createdAt: Date()),
        ])
        XCTAssertEqual(fixed, "hola Sintelia mi buen", fixed)
    }

    // MARK: - 6. Store invariants (dedup, relearn, prompt)

    /// Case-variant heard phrases ("Sintelia" vs "sintelia") collapse into ONE
    /// entry — apply keys on lowercase, so duplicates would be noise with
    /// nondeterministic precedence.
    func testCaseVariantHeardDeduplicates() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        XCTAssertNotNil(store.record(heard: "Sintelia", said: "Sinteliä"))
        env.clock.advance(seconds: 30)
        XCTAssertNotNil(store.record(heard: "sintelia", said: "Sinteliä"))
        XCTAssertEqual(store.all().count, 1, "case variants must dedupe")
    }

    /// After a manual delete, the same lesson can be re-learned later (the
    /// user tested exactly this and it must keep working).
    func testDeleteThenRelearnRoundTrips() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        let first = try XCTUnwrap(store.record(heard: "prueva", said: "prueba"))
        store.delete(id: first.id)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertNotNil(store.record(heard: "prueva", said: "prueba"))
        XCTAssertEqual(store.all().count, 1)
    }

    /// Re-recording updates the `said` but keeps the original creation date
    /// (prompt ordering stays stable).
    func testUpdateKeepsOriginalDate() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        let createdAt = env.clock.now
        XCTAssertNotNil(store.record(heard: "prueva", said: "prueba v1"))
        env.clock.advance(seconds: 3600)
        let updated = try XCTUnwrap(store.record(heard: "prueva", said: "prueba"))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(updated.createdAt, createdAt, "update must preserve creation date")
    }

    /// Prompt conditioning: newest terms first, hard budget respected.
    func testPromptNewestFirstWithinBudget() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let store = CorrectionStore(paths: env.paths, clock: env.clock)
        for i in 0..<12 {
            env.clock.advance(seconds: 60)
            store.record(heard: "h\(i)", said: "termino\(i) mas texto aqui")
        }
        let prompt = try XCTUnwrap(store.initialPrompt())
        XCTAssertLessThanOrEqual(prompt.count, 200)
        XCTAssertTrue(prompt.hasPrefix("termino11"), "newest first, got: \(prompt)")
    }
}
