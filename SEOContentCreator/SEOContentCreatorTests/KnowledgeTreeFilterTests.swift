import Testing
@testable import SEOContentCreator

struct KnowledgeTreeFilterTests {
    private func sample() -> [KnowledgeNode] {
        [
            KnowledgeNode(title: "Малоинвазивные операции", type: .advantage),
            KnowledgeNode(title: "Усычкин С.В.", type: .doctor),
            KnowledgeNode(title: "Лучевая терапия", type: .direction)
        ]
    }

    @Test func emptyFilterReturnsAll() {
        let f = KnowledgeTreeFilter()
        #expect(f.apply(to: sample()).count == 3)
    }

    @Test func searchMatchesTitle() {
        var f = KnowledgeTreeFilter()
        f.searchText = "усычкин"
        let r = f.apply(to: sample())
        #expect(r.count == 1)
        #expect(r.first?.nodeType == .doctor)
    }

    @Test func typeFilterNarrows() {
        var f = KnowledgeTreeFilter()
        f.types = [.advantage]
        let r = f.apply(to: sample())
        #expect(r.count == 1)
        #expect(r.first?.title == "Малоинвазивные операции")
    }
}
