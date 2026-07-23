import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticCollectionRunnerTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, SemanticKeyword.self, SemanticFunnelEntry.self,
            SemanticCollectionCheckpoint.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func checkpointPersistsOnATopicAndReadsBack() throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let checkpoint = SemanticCollectionCheckpoint(
            runID: UUID(),
            seeds: ["рак груди", "рак груди лечение"],
            stopWords: ["реферат"],
            masks: ["как"],
            threshold: 10,
            limit: 100
        )
        checkpoint.topic = topic
        context.insert(checkpoint)
        try context.save()

        #expect(topic.collectionCheckpoint === checkpoint)
        #expect(checkpoint.seeds == ["рак груди", "рак груди лечение"])
        #expect(checkpoint.completedSeeds.isEmpty)
        #expect(checkpoint.pulled.isEmpty)
        #expect(checkpoint.stopWordsSnapshot == ["реферат"])
        #expect(checkpoint.masksSnapshot == ["как"])
        #expect(checkpoint.thresholdSnapshot == 10)
        #expect(checkpoint.limitSnapshot == 100)
    }

    @Test func resetCheckpointDeletesIt() throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let checkpoint = SemanticCollectionCheckpoint(
            runID: UUID(), seeds: ["старый"],
            stopWords: [], masks: [], threshold: 10, limit: 100
        )
        checkpoint.topic = topic
        context.insert(checkpoint)
        try context.save()
        #expect(topic.collectionCheckpoint != nil)

        try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)

        #expect(topic.collectionCheckpoint == nil)
    }

    @Test func resetCheckpointIsANoOpWhenThereIsNoCheckpoint() throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)

        #expect(topic.collectionCheckpoint == nil)
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

    @Test func successfulRunRefreshesReaderIntentSemanticSnapshot() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let intent = ReaderIntent(
            query: "рак груди",
            hiddenGoal: "понять варианты лечения",
            semanticSnapshot: []
        )
        topic.readerIntent = intent
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение")],
                longTail: []
            )
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(intent.semanticSnapshot == ["рак груди лечение"])
        #expect(ReaderIntentStatus.forTopic(topic) == .ready(summary: "понять варианты лечения"))
    }

    @Test func saveFailureRestoresOnlySemanticMergeAndIntentSnapshot() async throws {
        struct FakeSaveError: Error {}

        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease, notes: "до запуска")
        let existing = SemanticKeyword(
            text: "рак груди лечение",
            frequency: 100,
            agentRecommendation: .none,
            userDecision: .required,
            reasonCategory: .other,
            explanation: "ручная пометка"
        )
        existing.topic = topic
        topic.semanticKeywords.append(existing)
        let intent = ReaderIntent(
            query: "рак груди",
            hiddenGoal: "понять варианты лечения",
            semanticSnapshot: ["старый запрос"]
        )
        topic.readerIntent = intent
        context.insert(topic)

        var runner = makeRunner(
            pulled: [
                WordstatPhrase(text: "рак груди лечение", frequency: 500),
                WordstatPhrase(text: "восстановление после лечения", frequency: 250)
            ],
            analysis: SemanticAgentAnalysis(
                keywords: [
                    includedResult("рак груди лечение"),
                    includedResult("восстановление после лечения")
                ],
                longTail: []
            )
        )
        runner.saveContext = { context in
            // Let every save succeed until the final merge save — i.e. until
            // SemanticKeywordMerger has actually added these two survivors to
            // topic.semanticKeywords in memory — then fail exactly that one,
            // so the test can assert the rollback restores only the merge
            // and intent-snapshot state, leaving the funnel journal and the
            // checkpoint's earlier progress-saves intact.
            let mergeHasHappened = topic.semanticKeywords.contains { $0.text == "рак груди лечение" }
                && topic.semanticKeywords.contains { $0.text == "восстановление после лечения" }
            if mergeHasHappened {
                throw FakeSaveError()
            }
            try context.save()
        }

        // Simulates an unrelated unsaved edit made before collection.
        topic.notes = "важная несохранённая заметка"
        let topicUpdatedAt = topic.updatedAt
        let intentUpdatedAt = intent.updatedAt

        await #expect(throws: FakeSaveError.self) {
            try await runner.run(topic: topic, pages: [], context: context)
        }

        #expect(topic.notes == "важная несохранённая заметка")
        #expect(topic.semanticKeywords.count == 1)
        #expect(topic.semanticKeywords.first === existing)
        #expect(existing.frequency == 100)
        #expect(existing.userDecision == .required)
        #expect(existing.reasonCategory == .other)
        #expect(existing.explanation == "ручная пометка")
        #expect(intent.semanticSnapshot == ["старый запрос"])
        #expect(topic.updatedAt == topicUpdatedAt)
        #expect(intent.updatedAt == intentUpdatedAt)
        #expect(!topic.funnelEntries.isEmpty)
        #expect(topic.collectionCheckpoint != nil)
    }

    @Test func failedRunDoesNotRefreshReaderIntentSemanticSnapshot() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let intent = ReaderIntent(
            query: "рак груди",
            hiddenGoal: "понять варианты лечения",
            semanticSnapshot: ["старый запрос"]
        )
        topic.readerIntent = intent
        context.insert(topic)

        let runner = makeRunner(
            pulled: [],
            analysis: SemanticAgentAnalysis(keywords: [], longTail: [])
        )

        await #expect(throws: SemanticCollectionRunner.RunError.self) {
            try await runner.run(topic: topic, pages: [], context: context)
        }

        #expect(intent.semanticSnapshot == ["старый запрос"])
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

    @Test func stopsTheRunImmediatelyWhenASeedFails() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        struct FakePullError: Error, LocalizedError {
            var errorDescription: String? { "квота исчерпана" }
        }

        var attemptedSeeds: [String] = []
        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["первый", "второй", "третий"], masks: [], tails: []) },
            pullPhrases: { seed in
                attemptedSeeds.append(seed)
                if seed == "второй" { throw FakePullError() }
                return [WordstatPhrase(text: "\(seed) запрос", frequency: 500)]
            },
            analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: [],
            masks: [],
            threshold: 10,
            limit: 100
        )

        await #expect(throws: FakePullError.self) {
            try await runner.run(topic: topic, pages: [], context: context)
        }

        #expect(attemptedSeeds == ["первый", "второй"])
        let failedSeed = topic.funnelEntries.first { $0.text == "второй" }
        #expect(failedSeed?.reason == "квота исчерпана")
        #expect(topic.semanticKeywords.isEmpty)
    }

    @Test func overwritesAnalyzerFrequencyWithRealWordstatFrequency() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        var keywordWithWrongFrequency = includedResult("рак груди лечение")
        keywordWithWrongFrequency.frequency = nil // simulates a model that echoed null

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(keywords: [keywordWithWrongFrequency], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords[0].frequency == 500)
    }

    @Test func wordstatReturnedNothingWhenEveryPullSucceedsButYieldsNoPhrases() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        // Every seed succeeds, but Wordstat genuinely has nothing for any of
        // them. This is the only way to reach the "no phrases" guard now that
        // any pullPhrases *error* aborts the run immediately instead of being
        // recorded-and-continued.
        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["рак груди"], masks: [], tails: []) },
            pullPhrases: { _ in [] },
            analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: [],
            masks: [],
            threshold: 10,
            limit: 100
        )

        await #expect(throws: SemanticCollectionRunner.RunError.self) {
            try await runner.run(topic: topic, pages: [], context: context)
        }

        // Nothing succeeded or failed — Wordstat legitimately had nothing to
        // say for any seed, so there is nothing to journal.
        #expect(topic.funnelEntries.isEmpty)
    }

    @Test func rulesDroppedEverythingErrorCarriesRunID() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            plan: SemanticSeedPlan(synonyms: ["рак груди"], masks: [], tails: []),
            pulled: [WordstatPhrase(text: "рак груди реферат", frequency: 900)],
            analysis: SemanticAgentAnalysis(keywords: [], longTail: [])
        )

        do {
            _ = try await runner.run(topic: topic, pages: [], context: context)
            Issue.record("Expected rulesDroppedEverything to be thrown")
        } catch let error as SemanticCollectionRunner.RunError {
            #expect(topic.funnelEntries.filter { $0.layer == .droppedByRules }.map(\.runID) == [error.runID])
        }
    }

    @Test func survivedEntryShowsLongTailExplanation() async throws {
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

        let longTailEntry = topic.funnelEntries.first { $0.text == "сколько длится лечение рака груди" && $0.layer == .survived }
        #expect(longTailEntry?.reason == "Длинный запрос, предложен агентом")
    }

    @Test func savesLargeFunnelJournalWithoutCrashing() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        // Matches the scale of the production crash (~9334 funnel entries total).
        let droppedCount = 4666
        var pulled: [WordstatPhrase] = (0..<droppedCount).map {
            WordstatPhrase(text: "запрос \($0)", frequency: 1)
        }
        pulled.append(WordstatPhrase(text: "рак груди лечение", frequency: 500))

        let runner = makeRunner(
            pulled: pulled,
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        // raw entries for every pulled phrase + droppedByRules for every low-frequency
        // phrase + one survived entry for the single keyword that made it through.
        #expect(topic.funnelEntries.count == (droppedCount + 1) + droppedCount + 1)
    }

    @Test func reportsPipelineStageAndWordstatCounter() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        var progress: [SemanticCollectionProgress] = []
        var runner = makeRunner(
            plan: SemanticSeedPlan(synonyms: ["рак груди", "рмж"], masks: [], tails: []),
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(
                keywords: [includedResult("рак груди лечение")],
                longTail: []
            )
        )
        runner.reportProgress = { progress.append($0) }

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(progress.contains(.planning))
        #expect(progress.contains(.wordstat(completed: 0, total: 2)))
        #expect(progress.contains(.wordstat(completed: 1, total: 2)))
        #expect(progress.contains(.wordstat(completed: 2, total: 2)))
        #expect(progress.contains(.relevance))
        #expect(progress.contains(.cannibalization))
        #expect(progress.last == .saving)
    }

    @Test func cancellationStopsSeedLoopAndLeavesSemanticsUntouched() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let existing = SemanticKeyword(text: "старый запрос", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords.append(existing)
        context.insert(topic)

        var pullCount = 0
        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in
                SemanticSeedPlan(synonyms: ["первый", "второй"], masks: [], tails: [])
            },
            pullPhrases: { _ in
                pullCount += 1
                try await Task.sleep(for: .seconds(30))
                return []
            },
            analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: [],
            masks: [],
            threshold: 10,
            limit: 100
        )

        let task = Task {
            try await runner.run(topic: topic, pages: [], context: context)
        }
        while pullCount == 0 {
            await Task.yield()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(pullCount == 1)
        #expect(topic.semanticKeywords.map(\.text) == ["старый запрос"])
    }

    @Test func deadlineCancelsRunnerAndLeavesSemanticsUntouched() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        let existing = SemanticKeyword(text: "старый запрос", userDecision: .accepted)
        existing.topic = topic
        topic.semanticKeywords.append(existing)
        context.insert(topic)

        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in
                SemanticSeedPlan(synonyms: ["медленный запрос"], masks: [], tails: [])
            },
            pullPhrases: { _ in
                try await Task.sleep(for: .seconds(30))
                return [WordstatPhrase(text: "новый запрос", frequency: 100)]
            },
            analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: [],
            masks: [],
            threshold: 10,
            limit: 100
        )

        await #expect(throws: SemanticCollectionDeadline.DeadlineError.self) {
            try await SemanticCollectionDeadline.run(timeout: .milliseconds(10)) {
                try await runner.run(topic: topic, pages: [], context: context)
            }
        }
        #expect(topic.semanticKeywords.map(\.text) == ["старый запрос"])
    }

    @Test func failingSeedLeavesACheckpointWithProgressSoFar() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        struct FakeWordstatError: Error, LocalizedError {
            var errorDescription: String? { "Wordstat недоступен" }
        }

        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in SemanticSeedPlan(synonyms: ["первый", "второй", "третий"], masks: [], tails: []) },
            pullPhrases: { seed in
                if seed == "второй" { throw FakeWordstatError() }
                return [WordstatPhrase(text: "\(seed) запрос", frequency: 500)]
            },
            analyzeRelevance: { _, _ in SemanticAgentAnalysis(keywords: [], longTail: []) },
            checkCannibalization: { keywords, _ in keywords },
            stopWords: ["минус"],
            masks: [],
            threshold: 10,
            limit: 100
        )

        await #expect(throws: FakeWordstatError.self) {
            try await runner.run(topic: topic, pages: [], context: context)
        }

        let checkpoint = try #require(topic.collectionCheckpoint)
        #expect(checkpoint.seeds == ["первый", "второй", "третий"])
        #expect(checkpoint.completedSeeds == ["первый"])
        #expect(checkpoint.pulled.map(\.text) == ["первый запрос"])
        #expect(checkpoint.stopWordsSnapshot == ["минус"])
        #expect(checkpoint.thresholdSnapshot == 10)
        #expect(checkpoint.limitSnapshot == 100)
    }

    @Test func resumingSkipsSeedsAlreadyInTheCheckpointAndDoesNotReplan() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let checkpoint = SemanticCollectionCheckpoint(
            runID: UUID(), seeds: ["первый", "второй"],
            stopWords: [], masks: [], threshold: 10, limit: 100
        )
        checkpoint.completedSeeds = ["первый"]
        checkpoint.pulled = [WordstatPhrase(text: "первый запрос", frequency: 500)]
        checkpoint.topic = topic
        context.insert(checkpoint)
        try context.save()

        var attemptedSeeds: [String] = []
        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in
                Issue.record("planSeeds must not be called when a checkpoint already exists")
                return SemanticSeedPlan(synonyms: [], masks: [], tails: [])
            },
            pullPhrases: { seed in
                attemptedSeeds.append(seed)
                return [WordstatPhrase(text: "второй запрос", frequency: 300)]
            },
            analyzeRelevance: { _, queries in
                SemanticAgentAnalysis(
                    keywords: queries.map {
                        SemanticAgentKeywordResult(
                            query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                            explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                        )
                    },
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

        #expect(attemptedSeeds == ["второй"])
        #expect(topic.semanticKeywords.map(\.text).sorted() == ["второй запрос", "первый запрос"])
    }

    @Test func resumedRunUsesSettingsFrozenAtFirstAttemptNotTheRunnersConstructorValues() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        // Frozen at the first attempt: no stop-words.
        let checkpoint = SemanticCollectionCheckpoint(
            runID: UUID(), seeds: ["рак груди реферат"],
            stopWords: [], masks: [], threshold: 10, limit: 100
        )
        checkpoint.topic = topic
        context.insert(checkpoint)
        try context.save()

        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in
                Issue.record("planSeeds must not be called when a checkpoint already exists")
                return SemanticSeedPlan(synonyms: [], masks: [], tails: [])
            },
            pullPhrases: { _ in [WordstatPhrase(text: "рак груди реферат", frequency: 900)] },
            analyzeRelevance: { _, queries in
                SemanticAgentAnalysis(
                    keywords: queries.map {
                        SemanticAgentKeywordResult(
                            query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                            explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                        )
                    },
                    longTail: []
                )
            },
            checkCannibalization: { keywords, _ in keywords },
            // Live setting now has a stop-word that would drop this phrase — but
            // the checkpoint's frozen (empty) snapshot must win.
            stopWords: ["реферат"],
            masks: [],
            threshold: 10,
            limit: 100
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.semanticKeywords.map(\.text) == ["рак груди реферат"])
    }

    @Test func successfulRunDeletesTheCheckpoint() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let runner = makeRunner(
            pulled: [WordstatPhrase(text: "рак груди лечение", frequency: 500)],
            analysis: SemanticAgentAnalysis(keywords: [includedResult("рак груди лечение")], longTail: [])
        )

        try await runner.run(topic: topic, pages: [], context: context)

        #expect(topic.collectionCheckpoint == nil)
    }

    @Test func resetCheckpointClearsProgressSoTheNextRunStartsFresh() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let oldCheckpoint = SemanticCollectionCheckpoint(
            runID: UUID(), seeds: ["старый"],
            stopWords: [], masks: [], threshold: 10, limit: 100
        )
        oldCheckpoint.completedSeeds = ["старый"]
        oldCheckpoint.pulled = [WordstatPhrase(text: "старый запрос", frequency: 500)]
        oldCheckpoint.topic = topic
        context.insert(oldCheckpoint)
        try context.save()

        try SemanticCollectionRunner.resetCheckpoint(for: topic, context: context)
        #expect(topic.collectionCheckpoint == nil)

        var plannedSeeds: [String] = []
        let runner = SemanticCollectionRunner(
            planSeeds: { _, _ in
                SemanticSeedPlan(synonyms: ["новый"], masks: [], tails: [])
            },
            pullPhrases: { seed in
                plannedSeeds.append(seed)
                return [WordstatPhrase(text: "новый запрос", frequency: 500)]
            },
            analyzeRelevance: { _, queries in
                SemanticAgentAnalysis(
                    keywords: queries.map {
                        SemanticAgentKeywordResult(
                            query: $0.text, frequency: nil, recommendation: .include, reasonCategory: .none,
                            explanation: "", cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
                        )
                    },
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

        #expect(plannedSeeds == ["новый"])
        #expect(topic.collectionCheckpoint == nil)
    }
}
