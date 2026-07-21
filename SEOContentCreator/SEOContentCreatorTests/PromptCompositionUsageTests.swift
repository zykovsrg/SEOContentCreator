import Testing
@testable import SEOContentCreator

struct PromptCompositionUsageTests {
    @Test func stageTitlesFollowsPipelineOrderForSharedRole() {
        let titles = PromptCompositionUsage.stageTitles(forRoleKey: "author")
        #expect(titles == ["Структура", "Черновик", "Продуктовые блоки", "Семантика-в-текст"])
    }

    @Test func stageTitlesForSingleStageRole() {
        #expect(PromptCompositionUsage.stageTitles(forRoleKey: "seo") == ["Проверка SEO"])
    }

    @Test func stageTitlesEmptyForUnknownRoleKey() {
        #expect(PromptCompositionUsage.stageTitles(forRoleKey: "nope").isEmpty)
    }

    @Test func roleNamesFollowCanonicalRoleOrder() {
        let author = AIRole(key: "author", name: "ИИ-автор", mandate: "", blockKeys: ["editorialPolicy"])
        let editor = AIRole(key: "editor", name: "ИИ-редактор", mandate: "", blockKeys: ["editorialPolicy"])
        let seo = AIRole(key: "seo", name: "ИИ-SEO", mandate: "", blockKeys: [])

        let names = PromptCompositionUsage.roleNames(forBlockKey: "editorialPolicy", in: [editor, seo, author])

        #expect(names == ["ИИ-автор", "ИИ-редактор"])
    }

    @Test func roleNamesEmptyWhenNoRoleUsesTheBlock() {
        let seo = AIRole(key: "seo", name: "ИИ-SEO", mandate: "", blockKeys: [])
        #expect(PromptCompositionUsage.roleNames(forBlockKey: "sources", in: [seo]).isEmpty)
    }
}
