import Testing
import Foundation
@testable import SEOContentCreator

@MainActor
struct SemanticSeedPlannerTests {
    private func makePlanner(response: String) -> SemanticSeedPlanner {
        SemanticSeedPlanner(
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

    @Test func returnsParsedPlan() async throws {
        let planner = makePlanner(response: """
        {"synonyms":["рак груди"],"masks":["как"],"tails":["лечение"]}
        """)
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        let plan = try await planner.plan(topic: topic, masks: ["как", "где"])

        #expect(plan.synonyms == ["рак груди"])
    }

    @Test func throwsOnEmptyResponse() async {
        let planner = makePlanner(response: "   ")
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        await #expect(throws: SemanticSeedPlanner.PlannerError.emptyResponse) {
            _ = try await planner.plan(topic: topic, masks: [])
        }
    }

    @Test func promptListsAllowedMasks() {
        let topic = Topic(title: "Рак молочной железы", articleType: .disease)

        let prompt = SemanticSeedPlanner.userPrompt(topic: topic, masks: ["как", "сколько"])

        #expect(prompt.contains("Рак молочной железы"))
        #expect(prompt.contains("как"))
        #expect(prompt.contains("сколько"))
    }
}
