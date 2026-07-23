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

    @Test func capsSeedPhrasesAtOneHundred() {
        // 5 synonyms × (1 + 30 masks + 30 tails) = 305 combinations without a cap.
        let plan = SemanticSeedPlan(
            synonyms: (1...5).map { "синоним\($0)" },
            masks: (1...30).map { "маска\($0)" },
            tails: (1...30).map { "хвост\($0)" }
        )

        #expect(plan.seedPhrases().count == SemanticSeedPlan.maxSeedPhrases)
        #expect(SemanticSeedPlan.maxSeedPhrases == 100)
    }

    @Test func prioritizesBareSynonymsFirstThenMasksRoundRobin() {
        // 2 synonyms + 2×60 mask combos + 2×60 tail combos = 242 candidates.
        // Under the 100 cap: both bare synonyms, then 98 mask combos spread
        // evenly across synonyms; tails must not make it in at all.
        let plan = SemanticSeedPlan(
            synonyms: ["первый", "второй"],
            masks: (1...60).map { "маска\($0)" },
            tails: (1...60).map { "хвост\($0)" }
        )

        let seeds = plan.seedPhrases()

        #expect(seeds.count == 100)
        #expect(Array(seeds.prefix(2)) == ["первый", "второй"])
        #expect(seeds[2] == "первый маска1")
        #expect(seeds[3] == "второй маска1")
        #expect(seeds[4] == "первый маска2")
        #expect(!seeds.contains { $0.contains("хвост") })

        let firstSynonymCount = seeds.filter { $0.hasPrefix("первый") }.count
        let secondSynonymCount = seeds.filter { $0.hasPrefix("второй") }.count
        #expect(abs(firstSynonymCount - secondSynonymCount) <= 1)
    }

    @Test func smallPlansAreNotTruncated() {
        let plan = SemanticSeedPlan(synonyms: ["рак груди"], masks: ["как"], tails: ["лечение"])

        let seeds = plan.seedPhrases()

        #expect(seeds == ["рак груди", "рак груди как", "рак груди лечение"])
    }
}
