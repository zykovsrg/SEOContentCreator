import Testing
@testable import SEOContentCreator

struct ContentPlanFilterTests {
    private func sample() -> [Topic] {
        [
            Topic(title: "Лечение рака простаты", articleType: .disease),
            Topic(title: "Услуга КТ-симуляция", articleType: .service),
            Topic(title: "Реабилитация", articleType: .info)
        ]
    }

    @Test func emptyFilterReturnsAll() {
        let f = ContentPlanFilter()
        #expect(f.apply(to: sample()).count == 3)
    }

    @Test func searchMatchesTitleCaseInsensitive() {
        var f = ContentPlanFilter()
        f.searchText = "простаты"
        let result = f.apply(to: sample())
        #expect(result.count == 1)
        #expect(result.first?.title == "Лечение рака простаты")
    }

    @Test func typeFilterNarrows() {
        var f = ContentPlanFilter()
        f.type = .service
        let result = f.apply(to: sample())
        #expect(result.count == 1)
        #expect(result.first?.articleType == .service)
    }
}
