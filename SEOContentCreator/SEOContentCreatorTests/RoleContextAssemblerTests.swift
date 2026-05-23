import Testing
@testable import SEOContentCreator

struct RoleContextAssemblerTests {
    @Test func assemblesMandateAndBlocksInCanonicalOrder() {
        let role = AIRole(
            key: "author",
            name: "ИИ-автор",
            mandate: "Мандат роли",
            blockKeys: ["seoGuidelines", "editorialPolicy", "sources"]
        )
        let blocks = [
            ContextBlock(key: "seoGuidelines", title: "SEO", text: "SEO-текст"),
            ContextBlock(key: "sources", title: "Источники", text: "Текст источников"),
            ContextBlock(key: "editorialPolicy", title: "Редполитика", text: "Текст редполитики")
        ]

        let result = RoleContextAssembler.assemble(role: role, blocks: blocks)

        #expect(result == "Мандат роли\n\nТекст редполитики\n\nТекст источников\n\nSEO-текст")
    }

    @Test func skipsEmptyPartsAndMissingBlocks() {
        let role = AIRole(
            key: "editor",
            name: "ИИ-редактор",
            mandate: "  ",
            blockKeys: ["editorialPolicy", "missing"]
        )
        let blocks = [
            ContextBlock(key: "editorialPolicy", title: "Редполитика", text: "\nПолитика\n"),
            ContextBlock(key: "sources", title: "Источники", text: "Не должен попасть")
        ]

        let result = RoleContextAssembler.assemble(role: role, blocks: blocks)

        #expect(result == "Политика")
    }
}
