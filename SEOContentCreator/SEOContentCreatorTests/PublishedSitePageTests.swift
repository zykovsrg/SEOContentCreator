import Testing
@testable import SEOContentCreator

struct PublishedSitePageTests {
    @Test func summaryForAgentOmitsEmptyFieldsButKeepsURL() {
        let page = PublishedSitePage(
            url: "https://hadassah.moscow/prostate",
            title: "",
            metaDescription: "  ",
            h1: [],
            h2: []
        )

        #expect(page.summaryForAgent == "URL: https://hadassah.moscow/prostate")
    }

    @Test func summaryForAgentIncludesNonEmptyFieldsInExpectedOrder() {
        let page = PublishedSitePage(
            url: "https://hadassah.moscow/prostate",
            title: "Лечение рака простаты",
            metaDescription: "Описание страницы",
            h1: ["Рак простаты"],
            h2: ["Диагностика", "Лечение"]
        )

        #expect(
            page.summaryForAgent ==
            """
            URL: https://hadassah.moscow/prostate
            Title: Лечение рака простаты
            Description: Описание страницы
            H1: Рак простаты
            H2: Диагностика | Лечение
            """
        )
    }
}
