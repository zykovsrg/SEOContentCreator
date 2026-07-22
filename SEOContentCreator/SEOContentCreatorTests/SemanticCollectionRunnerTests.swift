import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticCollectionRunnerTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, SemanticKeyword.self, SemanticFunnelEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeRunner(
        plan: SemanticSeedPlan = SemanticSeedPlan(synonyms: ["рак груди"], masks: [], tails: []),
        pulled: [WordstatPhrase],
        analysis: SemanticAgentAnalysis
    ) -> SemanticCollectionRunner {
        SemanticCollectionRunner(
            planSeeds: { _, _ in plan },
            pullPhrases: { _ in pulled },
            analyzeRelevance: { _, _ in analysis },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: ["реферат"],
            masks: ["как"],
            threshold: 10,
            limit: 100
        )
    }

    private func includedResult(_ query: String) -> SemanticAgentKeywordResult {
        SemanticAgentKeywordResult(
            query: query, frequency: nil, recommendation: .include, reasonCategory: .none,
            explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
        )
    }

    @Test func savesSurvivorsAsAcceptedKeywords() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords.map(\.text) == ["рак груди лечение"])
        #expect(topic.semanticKeywords[0].userDecision == .accepted)
    }

    @Test func recordsRuleDropsInFunnel() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди реферат", frequency: 900),
                WordstatPhrase(text: "рак груди лечение", frequency: 500)
            ],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        let dropped = topic.funnelEntries.filter { $0.layer == .droppedByRules }
        #expect(dropped.map(\.text) == ["рак груди реферат"])
        #expect(dropped[0].reason.contains("реферат"))
    }

    @Test func recordsRelevanceDropsInFunnel() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        var excluded = includedResult("рак груди форум")
        excluded.recommendation = .exclude
        excluded.reasonCategory = .offTopic

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди лечение", frequency: 500),
                WordstatPhrase(text: "рак груди форум", frequency: 400)
            ],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение"), excluded],
                longTail: []
            )
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords.map(\.text) == ["рак груди лечение"])
        #expect(topic.funnelEntries.filter { $0.layer == .droppedByRelevance }.map(\.text) == ["рак груди форум"])
    }

    @Test func addsLongTailQueriesWithoutFrequency() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение")],
                longTail: ["сколько длится лечение рака груди"]
            )
        )

        try await runner.run(topic: topic, pages: [], context: context)

        let longTail = topic.semanticKeywords.first { $0.text == "сколько длится лечение рака груди" }
        #expect(longTail != nil)
        #expect(longTail?.frequency == nil)
    }

    @Test func groupsEveryEntryUnderOneRunID() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди реферат", frequency: 900),
                WordstatPhrase(text: "рак груди лечение", frequency: 500)
            ],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(Set(topic.funnelEntries.map(\.runID)).count == 1)
    }

    @Test func recordsRealErrorMessageWhenASeedFails() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        struct FakePullError: Error, LocalizedError {
            var errorDescription: String? { "квота исчерпана" }
        }

        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["рак груди", "рмж"], masks: [], tails: []) },
            pullPhrases: { seed in
                if seed == "рмж" { throw FakePullError() }
                return [WordstatPhrase(text: "рак груди лечение", frequency: 500)]
            },
            analyzeRelevance: { _, _ in
                SemanticAgentAnalysis(
                    keywords: [SemanticAgentKeywordResult(
                        query: "рак груди лечение", frequency: nil, recommendation: .include, reasonCategory: .none,
                        explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                    )],
                    longTail: []
                )
            },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: [],
            masks: [],
            threshold: 10,
            limit: 100
        )

        try await runner.run(topic: topic, pages: [], context: context)

        let failedSeed = topic.funnelEntries.first { $0.text == "рмж" }
        #expect(failedSeed?.reason == "квота исчерпана")
    }
}
