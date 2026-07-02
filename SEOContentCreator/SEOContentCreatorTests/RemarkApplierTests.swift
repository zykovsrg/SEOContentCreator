import Testing
@testable import SEOContentCreator

struct RemarkApplierTests {
    private func remark(_ quote: String, _ suggestion: String) -> Remark {
        Remark(category: "C", quote: quote, suggestion: suggestion, explanation: "e")
    }

    @Test func appliesSingleReplacement() {
        let result = RemarkApplier.apply(base: "abc осуществляется def", accepted: [remark("осуществляется", "делается")])
        #expect(result == "abc делается def")
    }

    @Test func appliesMultipleReplacements() {
        let result = RemarkApplier.apply(
            base: "Цена 5000. Текст водянистый.",
            accepted: [remark("5000", "4500"), remark("водянистый", "ёмкий")]
        )
        #expect(result == "Цена 4500. Текст ёмкий.")
    }

    @Test func notFoundQuoteSkipped() {
        let result = RemarkApplier.apply(base: "abc", accepted: [remark("xyz", "qqq")])
        #expect(result == "abc")
    }

    @Test func emptyAcceptedReturnsBase() {
        #expect(RemarkApplier.apply(base: "abc", accepted: []) == "abc")
    }

    @Test func emptyQuoteSkipped() {
        #expect(RemarkApplier.apply(base: "abc", accepted: [remark("", "qqq")]) == "abc")
    }

    @Test func laterRemarkDoesNotMatchInsideEarlierSuggestion() {
        // remark1 inserts "старый" as part of its suggestion; remark2's quote
        // "старый" must NOT match inside that just-inserted text.
        let result = RemarkApplier.apply(
            base: "Это новый метод.",
            accepted: [remark("новый", "очень старый"), remark("старый", "древний")]
        )
        #expect(result == "Это очень старый метод.")
    }

    @Test func secondOccurrenceOfRepeatedQuoteInOriginalTextStillMatches() {
        // Two separate remarks quoting the same original phrase should each
        // land on a distinct occurrence, since the first is consumed in order.
        let result = RemarkApplier.apply(
            base: "Боль в спине. Позже боль в ноге.",
            accepted: [remark("оль", "*1*"), remark("оль", "*2*")]
        )
        #expect(result == "Б*1* в спине. Позже б*2* в ноге.")
    }

    @Test func skipsRemarkWhenOnlyRemainingMatchIsInsideProtectedText() {
        // remark1 consumes the only occurrence of "боль"; remark2 targets the
        // same quote again but nothing unprotected is left, so it is skipped.
        let result = RemarkApplier.apply(
            base: "боль в спине",
            accepted: [remark("боль", "дискомфорт"), remark("боль", "неприятное ощущение")]
        )
        #expect(result == "дискомфорт в спине")
    }
}
