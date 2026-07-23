import Foundation
import SwiftData

/// Orchestrates the whole collection pipeline. Every external dependency is a
/// closure so the whole run is testable without network or LLM access.
@MainActor
struct SemanticCollectionRunner {
    typealias SeedPlanner = (Topic, [String]) async throws -> SemanticSeedPlan
    typealias PhrasePuller = (String) async throws -> [WordstatPhrase]
    typealias RelevanceAnalyzer = (Topic, [WordstatPhrase]) async throws -> SemanticAgentAnalysis
    typealias CannibalizationChecker = ([SemanticAgentKeywordResult], [PublishedSitePage]) async throws -> [SemanticAgentKeywordResult]

    enum RunError: Error, LocalizedError, Equatable {
        case wordstatReturnedNothing(runID: UUID)
        case rulesDroppedEverything(runID: UUID)

        var errorDescription: String? {
            switch self {
            case .wordstatReturnedNothing:
                return "Wordstat не вернул ни одного запроса. Семантика темы не изменена."
            case .rulesDroppedEverything:
                return "Все собранные запросы отсеяны правилами (минус-слова или низкая частотность). Семантика темы не изменена."
            }
        }

        /// So a caller can still inspect the funnel journal recorded before the throw.
        var runID: UUID {
            switch self {
            case .wordstatReturnedNothing(let id), .rulesDroppedEverything(let id):
                return id
            }
        }
    }

    var planSeeds: SeedPlanner
    var pullPhrases: PhrasePuller
    var analyzeRelevance: RelevanceAnalyzer
    var checkCannibalization: CannibalizationChecker
    var stopWords: [String]
    var masks: [String]
    var threshold: Int
    var limit: Int

    @discardableResult
    func run(topic: Topic, pages: [PublishedSitePage], context: ModelContext) async throws -> UUID {
        let runID = UUID()

        let plan = try await planSeeds(topic, masks)

        var pulled: [WordstatPhrase] = []
        for seed in plan.seedPhrases() {
            // A failing seed must not abort the run; the funnel records why it failed.
            do {
                let phrases = try await pullPhrases(seed)
                pulled.append(contentsOf: phrases)
            } catch {
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: error.localizedDescription, runID: runID)
            }
        }

        guard !pulled.isEmpty else { throw RunError.wordstatReturnedNothing(runID: runID) }

        for phrase in pulled {
            record(topic: topic, context: context, text: phrase.text, frequency: phrase.frequency,
                   layer: .raw, reason: "", runID: runID)
        }

        let filtered = SemanticRuleFilter.apply(pulled, stopWords: stopWords, threshold: threshold, limit: limit)

        for drop in filtered.dropped {
            record(topic: topic, context: context, text: drop.phrase.text, frequency: drop.phrase.frequency,
                   layer: .droppedByRules, reason: drop.reason, runID: runID)
        }

        guard !filtered.survivors.isEmpty else { throw RunError.rulesDroppedEverything(runID: runID) }

        let realFrequencyByQuery = Dictionary(
            filtered.survivors.map { (SemanticRuleFilter.normalize($0.text), $0.frequency) },
            uniquingKeysWith: { first, _ in first }
        )
        let analysis = try await analyzeRelevance(topic, filtered.survivors)
        let keywordsWithRealFrequency = analysis.keywords.map { keyword -> SemanticAgentKeywordResult in
            var updated = keyword
            updated.frequency = realFrequencyByQuery[SemanticRuleFilter.normalize(keyword.query)]
            return updated
        }

        for keyword in keywordsWithRealFrequency where keyword.recommendation == .exclude {
            record(topic: topic, context: context, text: keyword.query, frequency: keyword.frequency,
                   layer: .droppedByRelevance,
                   reason: keyword.explanation.isEmpty ? keyword.reasonCategory.label : keyword.explanation,
                   runID: runID)
        }

        let included = keywordsWithRealFrequency.filter { $0.recommendation == .include }
        let checked = try await checkCannibalization(included, pages)

        let longTailResults = analysis.longTail.map { query in
            SemanticAgentKeywordResult(
                query: query, frequency: nil, recommendation: .include, reasonCategory: .none,
                explanation: "Длинный запрос, предложен агентом",
                cannibalizationRisk: .none, cannibalizationURL: nil, cannibalizationTitle: nil
            )
        }

        let survivors = checked + longTailResults

        for keyword in survivors {
            let riskNote = (keyword.cannibalizationRisk == .high || keyword.cannibalizationRisk == .medium)
                ? "Риск каннибализации: \(keyword.cannibalizationRisk.label)"
                : ""
            let reason = [riskNote, keyword.explanation].filter { !$0.isEmpty }.joined(separator: " — ")
            record(topic: topic, context: context, text: keyword.query, frequency: keyword.frequency,
                   layer: .survived, reason: reason, runID: runID)
        }

        SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
        try? context.save()

        return runID
    }

    private func record(
        topic: Topic, context: ModelContext, text: String, frequency: Int?,
        layer: SemanticFunnelLayer, reason: String, runID: UUID
    ) {
        let entry = SemanticFunnelEntry(text: text, frequency: frequency, layer: layer, reason: reason, runID: runID)
        entry.topic = topic
        context.insert(entry)
        topic.funnelEntries.append(entry)
    }
}
