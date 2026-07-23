import Testing
import Foundation
@testable import SEOContentCreator

@MainActor
struct SemanticCannibalizationCheckerTests {
    private func makeChecker(response: String) -> SemanticCannibalizationChecker {
        SemanticCannibalizationChecker(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.token(response))
                    continuation.finish()
                }
            },
            keyProvider: { "test-key" },
            model: "gpt-4.1"
        )
    }

    private func keyword(_ query: String) -> SemanticAgentKeywordResult {
        SemanticAgentKeywordResult(
            query: query,
            frequency: 100,
            recommendation: .include,
            reasonCategory: .none,
            explanation: "",
            cannibalizationRisk: .none,
            cannibalizationURL: nil,
            cannibalizationTitle: nil
        )
    }

    @Test func fillsCannibalizationFields() async throws {
        let checker = makeChecker(response: """
        {"results":[{"query":"рак груди лечение","risk":"high","url":"https://hadassah.moscow/rak-grudi","title":"Лечение рака груди"}]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .high)
        #expect(updated[0].cannibalizationURL == "https://hadassah.moscow/rak-grudi")
        #expect(updated[0].reasonCategory == .cannibalization)
    }

    @Test func leavesUnmentionedKeywordsUntouched() async throws {
        let checker = makeChecker(response: """
        {"results":[]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .none)
        #expect(updated[0].reasonCategory == .none)
    }

    @Test func skipsNetworkCallWhenNoPagesAndNoKeywords() async throws {
        let checker = makeChecker(response: "не должно вызываться")

        let updated = try await checker.check(keywords: [], pages: [])

        #expect(updated.isEmpty)
    }

    @Test func lowRiskDoesNotOverwriteReasonCategory() async throws {
        let checker = makeChecker(response: """
        {"results":[{"query":"рак груди лечение","risk":"low","url":null,"title":null}]}
        """)

        let updated = try await checker.check(keywords: [keyword("рак груди лечение")], pages: [])

        #expect(updated[0].cannibalizationRisk == .low)
        #expect(updated[0].reasonCategory == .none)
    }

    @Test func promptAssignsCannibalizationCheckToAI() {
        #expect(SemanticCannibalizationChecker.systemPrompt.contains("Самостоятельно"))
        #expect(SemanticCannibalizationChecker.systemPrompt.contains("опубликованными страницами"))
        #expect(SemanticCannibalizationChecker.systemPrompt.contains("без стороннего сервиса"))
    }
}
