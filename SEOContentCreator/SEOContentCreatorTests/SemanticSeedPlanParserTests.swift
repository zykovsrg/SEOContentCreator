import Testing
@testable import SEOContentCreator

struct SemanticSeedPlanParserTests {
    @Test func parsesValidPlan() throws {
        let json = """
        {"synonyms":["рак груди","РМЖ"],"masks":["как","сколько"],"tails":["лечение","цена"]}
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["рак груди", "РМЖ"])
        #expect(plan.masks == ["как", "сколько"])
        #expect(plan.tails == ["лечение", "цена"])
    }

    @Test func trimsAndDropsBlankEntries() throws {
        let json = """
        {"synonyms":["  рак груди  ","","РМЖ"],"masks":[],"tails":["   "]}
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["рак груди", "РМЖ"])
        #expect(plan.masks.isEmpty)
        #expect(plan.tails.isEmpty)
    }

    @Test func stripsMarkdownFence() throws {
        let json = """
        ```json
        {"synonyms":["РМЖ"],"masks":[],"tails":[]}
        ```
        """

        let plan = try SemanticSeedPlanParser.parse(json)

        #expect(plan.synonyms == ["РМЖ"])
    }

    @Test func throwsOnMalformedJSON() {
        #expect(throws: SemanticSeedPlanParser.ParserError.badResponse) {
            try SemanticSeedPlanParser.parse("не json")
        }
    }

    @Test func throwsWhenAllListsAreEmpty() {
        #expect(throws: SemanticSeedPlanParser.ParserError.badResponse) {
            try SemanticSeedPlanParser.parse("""
            {"synonyms":[],"masks":[],"tails":[]}
            """)
        }
    }

    @Test func buildsSeedPhrasesFromPlan() {
        let plan = SemanticSeedPlan(synonyms: ["рак груди", "РМЖ"], masks: ["как"], tails: ["лечение"])

        let seeds = plan.seedPhrases()

        #expect(seeds.contains("рак груди"))
        #expect(seeds.contains("рак груди лечение"))
        #expect(seeds.contains("рмж как"))
        #expect(Set(seeds).count == seeds.count)
    }
}
