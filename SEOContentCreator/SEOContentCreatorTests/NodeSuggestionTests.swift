import Testing
@testable import SEOContentCreator

struct NodeSuggestionTests {
    private func directions() -> [KnowledgeNode] {
        [
            KnowledgeNode(title: "Лучевая терапия", type: .direction),
            KnowledgeNode(title: "Урология", type: .direction)
        ]
    }

    @Test func suggestsByTitleOverlap() {
        let s = NodeSuggestion.suggestDirections(
            forTopicTitle: "Лучевая терапия при раке простаты",
            from: directions()
        )
        #expect(s.first?.title == "Лучевая терапия")
    }

    @Test func noMatchReturnsEmpty() {
        let s = NodeSuggestion.suggestDirections(
            forTopicTitle: "Кардиология",
            from: directions()
        )
        #expect(s.isEmpty)
    }
}
