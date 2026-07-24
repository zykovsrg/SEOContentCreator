import Testing
@testable import SEOContentCreator

struct RemarkApplierTests {
    private func remark(_ quote: String, _ suggestion: String) -> Remark {
        Remark(category: "C", quote: quote, suggestion: suggestion, explanation: "e")
    }

    @Test func appliesSingleReplacement() {
        let result = RemarkApplier.apply(base: "abc осуществляется def", accepted: [remark("осуществляется", "делается")])
        #expect(result.text == "abc делается def")
        #expect(result.unresolvedIDs.isEmpty)
    }

    @Test func appliesMultipleReplacements() {
        let result = RemarkApplier.apply(
            base: "Цена 5000. Текст водянистый.",
            accepted: [remark("5000", "4500"), remark("водянистый", "ёмкий")]
        )
        #expect(result.text == "Цена 4500. Текст ёмкий.")
    }

    @Test func notFoundQuoteIsAppendedNotDropped() {
        // The correction must never vanish silently: since it can't be placed inline,
        // it lands in a clearly marked trailing block instead.
        let r = remark("совершенно другого текста здесь нет", "qqq")
        let result = RemarkApplier.apply(base: "abc", accepted: [r])
        #expect(result.appendedIDs == [r.id])
        #expect(result.unresolvedIDs.isEmpty)
        #expect(result.text.hasPrefix("abc"))
        #expect(result.text.contains("совершенно другого текста здесь нет"))
        #expect(result.text.contains("qqq"))
    }

    @Test func notFoundRemovalSuggestionIsUnresolvedNotAppended() {
        // Nothing to add: the suggestion was to remove text that isn't there.
        let r = remark("совершенно другого текста здесь нет", "")
        let result = RemarkApplier.apply(base: "abc", accepted: [r])
        #expect(result.text == "abc")
        #expect(result.unresolvedIDs == [r.id])
        #expect(result.appendedIDs.isEmpty)
    }

    @Test func emptyAcceptedReturnsBase() {
        let result = RemarkApplier.apply(base: "abc", accepted: [])
        #expect(result.text == "abc")
        #expect(result.unresolvedIDs.isEmpty)
    }

    @Test func emptyQuoteSkippedButNotUnresolved() {
        // An empty quote is advisory (nothing to place), not a failed match.
        let result = RemarkApplier.apply(base: "abc", accepted: [remark("", "qqq")])
        #expect(result.text == "abc")
        #expect(result.unresolvedIDs.isEmpty)
    }

    @Test func laterRemarkDoesNotMatchInsideEarlierSuggestion() {
        // "старый" must not match inside the "очень старый" the first remark just
        // inserted — since it's now unfindable unprotected, it is appended instead
        // of silently skipped (never dropping a correction).
        let r2 = remark("старый", "древний")
        let result = RemarkApplier.apply(
            base: "Это новый метод.",
            accepted: [remark("новый", "очень старый"), r2]
        )
        #expect(result.text.hasPrefix("Это очень старый метод."))
        #expect(result.appendedIDs == [r2.id])
    }

    @Test func secondOccurrenceOfRepeatedQuoteInOriginalTextStillMatches() {
        let result = RemarkApplier.apply(
            base: "Боль в спине. Позже боль в ноге.",
            accepted: [remark("оль", "[1]"), remark("оль", "[2]")]
        )
        #expect(result.text == "Б[1] в спине. Позже б[2] в ноге.")
    }

    @Test func appendsRemarkWhenOnlyRemainingMatchIsInsideProtectedText() {
        let r2 = remark("боль", "неприятное ощущение")
        let result = RemarkApplier.apply(
            base: "боль в спине",
            accepted: [remark("боль", "дискомфорт"), r2]
        )
        #expect(result.text.hasPrefix("дискомфорт в спине"))
        #expect(result.text.contains("неприятное ощущение"))
        #expect(result.appendedIDs == [r2.id])
    }

    // MARK: - Tolerant matching (LLM quotes rarely match the text byte-for-byte)

    @Test func matchesAcrossCollapsedWhitespace() {
        // Base has a double space / newline the model normalised away in its quote.
        let result = RemarkApplier.apply(
            base: "Фаст  Форвард\nобычно проводят",
            accepted: [remark("Фаст Форвард обычно", "Метод")]
        )
        #expect(result.text == "Метод проводят")
    }

    @Test func matchesInsideMarkdownEmphasis() {
        // Quote omits the ** the article wraps the phrase in; the bold markers stay put.
        let result = RemarkApplier.apply(
            base: "это **после операции** обычно",
            accepted: [remark("после операции", "до лечения")]
        )
        #expect(result.text == "это **до лечения** обычно")
    }

    @Test func matchesAcrossCurlyQuotesAndDash() {
        let result = RemarkApplier.apply(
            base: "врач называет «Фаст-Форвард» так",
            accepted: [remark("\"Фаст-Форвард\"", "метод")]
        )
        #expect(result.text == "врач называет метод так")
    }

    @Test func matchesEnDashQuotedWithHyphen() {
        let result = RemarkApplier.apply(
            base: "курс длится 5–7 дней подряд",
            accepted: [remark("5-7 дней", "одну неделю")]
        )
        #expect(result.text == "курс длится одну неделю подряд")
    }

    @Test func matchesIgnoringYoAndCase() {
        let result = RemarkApplier.apply(
            base: "Приём даёт эффект",
            accepted: [remark("прием дает", "курс обеспечивает")]
        )
        #expect(result.text == "курс обеспечивает эффект")
    }

    @Test func quoteThatIsOnlyPunctuationIsUnresolvedNotFalseMatched() {
        // A quote that normalises to nothing must never silently "match".
        let r = remark("**", "x")
        let result = RemarkApplier.apply(base: "текст **жирный** текст", accepted: [r])
        #expect(result.text == "текст **жирный** текст")
        #expect(result.unresolvedIDs == [r.id])
    }

    // MARK: - Title/H1/Description remarks (fields outside the article body)

    @Test func emptyTitleRemarkSetsSeoTitleDirectly() {
        // Reproduces the reported bug: an empty Title has no text in the body to quote,
        // so the fix must go straight to the metadata field, not a body search.
        let r = remark("Title:", "Title: Фаст Форвард при раке груди — лучевая терапия за 5 сеансов")
        let result = RemarkApplier.apply(base: "Текст статьи без изменений.", accepted: [r])
        #expect(result.text == "Текст статьи без изменений.")
        #expect(result.metadataEdits[.seoTitle] == "Фаст Форвард при раке груди — лучевая терапия за 5 сеансов")
        #expect(result.unresolvedIDs.isEmpty)
        #expect(result.appendedIDs.isEmpty)
    }

    @Test func h1AndDescriptionRemarksRouteToTheirFields() {
        let result = RemarkApplier.apply(
            base: "Текст.",
            accepted: [
                remark("H1:", "H1: Новый заголовок H1"),
                remark("Description:", "Description: Новое описание страницы")
            ]
        )
        #expect(result.metadataEdits[.h1] == "Новый заголовок H1")
        #expect(result.metadataEdits[.seoDescription] == "Новое описание страницы")
        #expect(result.text == "Текст.")
    }

    @Test func metadataRemarkWithoutEchoedLabelStillWorks() {
        // The model doesn't always repeat "Title:" in the suggestion itself.
        let r = remark("Title:", "Короткий тайтл без повтора метки")
        let result = RemarkApplier.apply(base: "Текст.", accepted: [r])
        #expect(result.metadataEdits[.seoTitle] == "Короткий тайтл без повтора метки")
    }
}
