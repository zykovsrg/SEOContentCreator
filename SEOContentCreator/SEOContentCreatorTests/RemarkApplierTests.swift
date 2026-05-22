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
}
