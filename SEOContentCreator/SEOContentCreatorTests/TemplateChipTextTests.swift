// TemplateChipTextTests.swift
import Testing
@testable import SEOContentCreator

struct TemplateChipTextTests {
    @Test func tokensUnderThousandShownRaw() {
        #expect(TemplateChipText.tokens(800) == "800")
    }
    @Test func tokensRoundedToK() {
        #expect(TemplateChipText.tokens(8000) == "8k")
        #expect(TemplateChipText.tokens(11000) == "11k")
    }
    @Test func tokensNonRoundKeepsOneDecimal() {
        #expect(TemplateChipText.tokens(11500) == "11.5k")
    }
    @Test func chipJoinsModelTokensAndReasoning() {
        #expect(TemplateChipText.chip(model: "gpt-5.5", maxTokens: 11000, reasoning: "high")
                == "gpt-5.5 · 11k · high")
    }
    @Test func chipOmitsReasoningWhenNil() {
        #expect(TemplateChipText.chip(model: "gpt-4.1", maxTokens: 8000, reasoning: nil)
                == "gpt-4.1 · 8k")
    }
    @Test func categoriesCoverAllFourGroups() {
        #expect(TemplateCategory.allCases.count == 4)
        #expect(TemplateCategory.allCases.first == .stages)
    }
}
