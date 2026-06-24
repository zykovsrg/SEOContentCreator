import Testing
@testable import SEOContentCreator

struct SoftHintsTests {
    // MARK: Long sentences

    @Test func flagsSentenceOverLimit() {
        let long = Array(repeating: "слово", count: 12).joined(separator: " ") + "."
        let hints = SoftHints.analyze(
            text: long,
            settings: SoftHintsSettings(longSentenceWordLimit: 10, repeatWindowWords: 30, cliches: [])
        )
        let longOnes = hints.filter { $0.kind == .longSentence }
        #expect(longOnes.count == 1)
    }

    @Test func ignoresSentenceAtOrUnderLimit() {
        let short = Array(repeating: "слово", count: 10).joined(separator: " ") + "."
        let hints = SoftHints.analyze(
            text: short,
            settings: SoftHintsSettings(longSentenceWordLimit: 10, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .longSentence }.isEmpty)
    }

    @Test func splitsOnTerminatorsAndNewlines() {
        // Two long sentences separated by a newline → two hints.
        let one = Array(repeating: "раз", count: 6).joined(separator: " ")
        let text = "\(one).\n\(one)?"
        let hints = SoftHints.analyze(
            text: text,
            settings: SoftHintsSettings(longSentenceWordLimit: 5, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .longSentence }.count == 2)
    }

    @Test func handlesEmptyText() {
        let hints = SoftHints.analyze(text: "", settings: .default)
        #expect(hints.isEmpty)
    }

    // MARK: Repeated roots

    @Test func flagsRepeatedRootWithinWindow() {
        let hints = SoftHints.analyze(
            text: "Обработка данных требует обработать поток.",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.count == 1)
    }

    @Test func ignoresRepeatedRootOutsideWindow() {
        // Filler words are <5 letters: skipped for root-matching, but they still
        // occupy word positions, so they push the two "обраб…" words apart.
        let filler = Array(repeating: "да", count: 10).joined(separator: " ")
        let text = "обработка \(filler) обработать"
        let hints = SoftHints.analyze(
            text: text,
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 3, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.isEmpty)
    }

    @Test func flagsExactWordRepeat() {
        let hints = SoftHints.analyze(
            text: "качество и ещё раз качество важно",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.count == 1)
    }

    @Test func ignoresShortWordsForRoots() {
        // "и", "на", "это" are <5 letters → no root repeats even if duplicated nearby.
        let hints = SoftHints.analyze(
            text: "это и это и это",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30, cliches: [])
        )
        #expect(hints.filter { $0.kind == .repeatedRoot }.isEmpty)
    }

    // MARK: Clichés

    @Test func findsClicheCaseAndYoInsensitive() {
        let hints = SoftHints.analyze(
            text: "В Наше Время всё иначе.",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["в наше время"])
        )
        #expect(hints.filter { $0.kind == .cliche }.count == 1)
    }

    @Test func findsMultipleClicheOccurrences() {
        let hints = SoftHints.analyze(
            text: "так или иначе, так или иначе снова",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["так или иначе"])
        )
        #expect(hints.filter { $0.kind == .cliche }.count == 2)
    }

    @Test func ignoresClicheInsideLongerWord() {
        // "акт" must not match inside "контакт".
        let hints = SoftHints.analyze(
            text: "наш контакт здесь",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["акт"])
        )
        #expect(hints.filter { $0.kind == .cliche }.isEmpty)
    }

    @Test func ignoresEmptyDictionaryEntries() {
        let hints = SoftHints.analyze(
            text: "обычный текст",
            settings: SoftHintsSettings(longSentenceWordLimit: 100, repeatWindowWords: 30,
                                        cliches: ["", "   "])
        )
        #expect(hints.filter { $0.kind == .cliche }.isEmpty)
    }

    // MARK: EditorDictionary mapping

    @Test func dictionaryParsesClichesAndBuildsSettings() {
        let dict = EditorDictionary(
            clichesText: "в наше время\n\n  так или иначе  \n",
            longSentenceWordLimit: 25,
            repeatWindowWords: 15
        )
        #expect(dict.cliches == ["в наше время", "так или иначе"])
        let s = dict.settings
        #expect(s.longSentenceWordLimit == 25)
        #expect(s.repeatWindowWords == 15)
        #expect(s.cliches.count == 2)
    }

    @Test func defaultsAreNonEmpty() {
        #expect(EditorDictionaryDefaults.longSentenceWordLimit > 0)
        #expect(EditorDictionaryDefaults.repeatWindowWords > 0)
        #expect(!EditorDictionaryDefaults.clichesText.isEmpty)
    }
}
