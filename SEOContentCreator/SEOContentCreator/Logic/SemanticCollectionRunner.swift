import Foundation
import SwiftData

enum SemanticCollectionProgress: Equatable, Sendable {
    case planning
    case wordstat(completed: Int, total: Int)
    case filtering
    case relevance
    case cannibalization
    case saving

    var label: String {
        switch self {
        case .planning:
            return "Планирую запросы с ИИ…"
        case .wordstat(let completed, let total):
            return "Получаю данные Wordstat: \(completed) из \(total)"
        case .filtering:
            return "Очищаю и группирую запросы…"
        case .relevance:
            return "ИИ проверяет релевантность…"
        case .cannibalization:
            return "ИИ проверяет каннибализацию…"
        case .saving:
            return "Сохраняю результат…"
        }
    }
}

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
    var saveContext: (ModelContext) throws -> Void = { try $0.save() }
    var reportProgress: (SemanticCollectionProgress) -> Void = { _ in }

    /// Keeps a single `context.save()` transaction from having to encode the
    /// whole Wordstat journal (thousands of entries) at once.
    private static let funnelSaveChunkSize = 200

    @discardableResult
    func run(topic: Topic, pages: [PublishedSitePage], context: ModelContext) async throws -> UUID {
        let runID = UUID()

        reportProgress(.planning)
        try Task.checkCancellation()
        let plan = try await planSeeds(topic, masks)
        try Task.checkCancellation()

        var pulled: [WordstatPhrase] = []
        let seeds = plan.seedPhrases()
        reportProgress(.wordstat(completed: 0, total: seeds.count))
        for (index, seed) in seeds.enumerated() {
            try Task.checkCancellation()
            // A failing seed must not abort the run; the funnel records why it failed.
            do {
                let phrases = try await pullPhrases(seed)
                try Task.checkCancellation()
                pulled.append(contentsOf: phrases)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                record(topic: topic, context: context, text: seed, frequency: nil,
                       layer: .raw, reason: error.localizedDescription, runID: runID)
            }
            reportProgress(.wordstat(completed: index + 1, total: seeds.count))
        }

        guard !pulled.isEmpty else { throw RunError.wordstatReturnedNothing(runID: runID) }

        try recordInChunks(pulled, topic: topic, context: context, runID: runID) { phrase in
            (text: phrase.text, frequency: phrase.frequency, layer: .raw, reason: "")
        }

        reportProgress(.filtering)
        try Task.checkCancellation()
        let filtered = SemanticRuleFilter.apply(pulled, stopWords: stopWords, threshold: threshold, limit: limit)

        try recordInChunks(filtered.dropped, topic: topic, context: context, runID: runID) { drop in
            (text: drop.phrase.text, frequency: drop.phrase.frequency, layer: .droppedByRules, reason: drop.reason)
        }

        guard !filtered.survivors.isEmpty else { throw RunError.rulesDroppedEverything(runID: runID) }

        let realFrequencyByQuery = Dictionary(
            filtered.survivors.map { (SemanticRuleFilter.normalize($0.text), $0.frequency) },
            uniquingKeysWith: { first, _ in first }
        )
        reportProgress(.relevance)
        let analysis = try await analyzeRelevance(topic, filtered.survivors)
        try Task.checkCancellation()
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
        reportProgress(.cannibalization)
        let checked = try await checkCannibalization(included, pages)
        try Task.checkCancellation()

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

        let rollback = SemanticMergeRollback.capture(topic: topic)
        do {
            reportProgress(.saving)
            try Task.checkCancellation()
            SemanticKeywordMerger.merge(survivors, into: topic, decision: .accepted)
            if let intent = topic.readerIntent {
                intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
                intent.updatedAt = .now
            }
            try saveContext(context)
        } catch {
            rollback.restore(topic: topic, context: context)
            throw error
        }

        return runID
    }

    /// Records and saves `items` in small batches so a single `context.save()`
    /// never has to encode the whole Wordstat journal (thousands of entries) at
    /// once, and so CoreData/SwiftData's autoreleased bridging objects are
    /// drained per batch instead of piling up for the whole async task.
    private func recordInChunks<T>(
        _ items: [T], topic: Topic, context: ModelContext, runID: UUID,
        describe: (T) -> (text: String, frequency: Int?, layer: SemanticFunnelLayer, reason: String)
    ) throws {
        for chunkStart in stride(from: 0, to: items.count, by: Self.funnelSaveChunkSize) {
            try autoreleasepool {
                let chunkEnd = min(chunkStart + Self.funnelSaveChunkSize, items.count)
                for item in items[chunkStart..<chunkEnd] {
                    let described = describe(item)
                    record(topic: topic, context: context, text: described.text, frequency: described.frequency,
                           layer: described.layer, reason: described.reason, runID: runID)
                }
                try saveContext(context)
            }
        }
    }

    private func record(
        topic: Topic, context: ModelContext, text: String, frequency: Int?,
        layer: SemanticFunnelLayer, reason: String, runID: UUID
    ) {
        let entry = SemanticFunnelEntry(text: text, frequency: frequency, layer: layer, reason: reason, runID: runID)
        entry.topic = topic
        context.insert(entry)
    }
}

private struct SemanticMergeRollback {
    struct KeywordState {
        let keyword: SemanticKeyword
        let frequency: Int?
        let agentRecommendationRaw: String
        let userDecisionRaw: String
        let reasonCategoryRaw: String
        let explanation: String
        let cannibalizationRiskRaw: String
        let cannibalizationURL: String?
        let cannibalizationTitle: String?
        let updatedAt: Date

        init(_ keyword: SemanticKeyword) {
            self.keyword = keyword
            frequency = keyword.frequency
            agentRecommendationRaw = keyword.agentRecommendationRaw
            userDecisionRaw = keyword.userDecisionRaw
            reasonCategoryRaw = keyword.reasonCategoryRaw
            explanation = keyword.explanation
            cannibalizationRiskRaw = keyword.cannibalizationRiskRaw
            cannibalizationURL = keyword.cannibalizationURL
            cannibalizationTitle = keyword.cannibalizationTitle
            updatedAt = keyword.updatedAt
        }

        func restore() {
            keyword.frequency = frequency
            keyword.agentRecommendationRaw = agentRecommendationRaw
            keyword.userDecisionRaw = userDecisionRaw
            keyword.reasonCategoryRaw = reasonCategoryRaw
            keyword.explanation = explanation
            keyword.cannibalizationRiskRaw = cannibalizationRiskRaw
            keyword.cannibalizationURL = cannibalizationURL
            keyword.cannibalizationTitle = cannibalizationTitle
            keyword.updatedAt = updatedAt
        }
    }

    let originalKeywordIDs: Set<UUID>
    let keywordStates: [KeywordState]
    let topicUpdatedAt: Date
    let intent: ReaderIntent?
    let intentSemanticSnapshot: [String]?
    let intentUpdatedAt: Date?

    static func capture(topic: Topic) -> Self {
        Self(
            originalKeywordIDs: Set(topic.semanticKeywords.map(\.uuid)),
            keywordStates: topic.semanticKeywords.map(KeywordState.init),
            topicUpdatedAt: topic.updatedAt,
            intent: topic.readerIntent,
            intentSemanticSnapshot: topic.readerIntent?.semanticSnapshot,
            intentUpdatedAt: topic.readerIntent?.updatedAt
        )
    }

    func restore(topic: Topic, context: ModelContext) {
        let newKeywords = topic.semanticKeywords.filter { !originalKeywordIDs.contains($0.uuid) }
        topic.semanticKeywords.removeAll { !originalKeywordIDs.contains($0.uuid) }
        for keyword in newKeywords {
            context.delete(keyword)
        }
        keywordStates.forEach { $0.restore() }
        topic.updatedAt = topicUpdatedAt
        if let intent {
            intent.semanticSnapshot = intentSemanticSnapshot ?? []
            if let intentUpdatedAt {
                intent.updatedAt = intentUpdatedAt
            }
        }
    }
}
