import Testing
@testable import SEOContentCreator

struct SemanticAgentResponseParserTests {
    @Test func parsesValidAgentJSON() throws {
        let json = """
        {
          "keywords": [
            {
              "query": "лечение рака простаты",
              "frequency": 120,
              "recommendation": "exclude",
              "reasonCategory": "cannibalization",
              "explanation": "Похоже на существующую страницу.",
              "cannibalizationRisk": "high",
              "cannibalizationURL": "https://hadassah.moscow/prostate",
              "cannibalizationTitle": "Рак простаты"
            }
          ]
        }
        """

        let parsed = try SemanticAgentResponseParser.parse(json)

        #expect(parsed.keywords.count == 1)
        #expect(parsed.keywords[0].query == "лечение рака простаты")
        #expect(parsed.keywords[0].frequency == 120)
        #expect(parsed.keywords[0].recommendation == .exclude)
        #expect(parsed.keywords[0].reasonCategory == .cannibalization)
        #expect(parsed.keywords[0].cannibalizationRisk == .high)
    }

    @Test func trimsQuery() throws {
        let json = """
        {
          "keywords": [
            {
              "query": "  рак простаты цена  ",
              "frequency": null,
              "recommendation": "include",
              "reasonCategory": "none",
              "explanation": "Подходит теме.",
              "cannibalizationRisk": "none",
              "cannibalizationURL": null,
              "cannibalizationTitle": null
            }
          ]
        }
        """

        let parsed = try SemanticAgentResponseParser.parse(json)

        #expect(parsed.keywords.count == 1)
        #expect(parsed.keywords[0].query == "рак простаты цена")
    }

    @Test func rejectsUnknownEnumValues() {
        let json = """
        {
          "keywords": [
            {
              "query": "рак простаты цена",
              "frequency": null,
              "recommendation": "maybe",
              "reasonCategory": "none",
              "explanation": "Нестандартные значения не должны проходить.",
              "cannibalizationRisk": "none",
              "cannibalizationURL": null,
              "cannibalizationTitle": null
            }
          ]
        }
        """

        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse(json)
        }
    }

    @Test func rejectsEmptyQueryAfterTrimming() {
        let json = """
        {
          "keywords": [
            {
              "query": "   ",
              "frequency": 20,
              "recommendation": "include",
              "reasonCategory": "none",
              "explanation": "",
              "cannibalizationRisk": "low",
              "cannibalizationURL": null,
              "cannibalizationTitle": null
            }
          ]
        }
        """

        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse(json)
        }
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse("{bad")
        }
    }

    @Test func rejectsUnexpectedEnvelope() {
        let json = #"{"items":[]}"#

        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse(json)
        }
    }

    @Test func rejectsMissingRequiredFields() {
        let json = #"{"keywords":[{"query":"рак простаты"}]}"#

        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse(json)
        }
    }

    @Test func rejectsWrongFieldTypes() {
        let json = """
        {
          "keywords": [
            {
              "query": "рак простаты",
              "frequency": "often",
              "recommendation": "include",
              "reasonCategory": "none",
              "explanation": "Подходит теме.",
              "cannibalizationRisk": "none",
              "cannibalizationURL": null,
              "cannibalizationTitle": null
            }
          ]
        }
        """

        #expect(throws: SemanticAgentResponseParser.ParserError.badResponse) {
            try SemanticAgentResponseParser.parse(json)
        }
    }

    @Test func parsesLongTailQueries() throws {
        let json = """
        {"keywords":[{"query":"рак груди лечение","frequency":100,"recommendation":"include","reasonCategory":"none","explanation":""}],"longTail":["сколько длится лечение рака груди","можно ли вылечить рак груди полностью"]}
        """

        let analysis = try SemanticAgentResponseParser.parse(json)

        #expect(analysis.keywords.count == 1)
        #expect(analysis.longTail.count == 2)
    }

    @Test func defaultsCannibalizationFieldsWhenAbsent() throws {
        let json = """
        {"keywords":[{"query":"рак груди","frequency":null,"recommendation":"include","reasonCategory":"none","explanation":""}]}
        """

        let analysis = try SemanticAgentResponseParser.parse(json)

        #expect(analysis.keywords[0].cannibalizationRisk == .none)
        #expect(analysis.keywords[0].cannibalizationURL == nil)
        #expect(analysis.longTail.isEmpty)
    }
}
