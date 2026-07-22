import Foundation
import SwiftData

struct ReaderIntentDraft: Equatable {
    var query = ""
    var audienceContext = ""
    var hiddenGoal = ""
    var successCriterion = ""
    var barriers = ""
    var solutionType: ReaderIntentSolutionType = .explanation
    var solutionFormat = ""
    var coverage: Set<ReaderIntentCoverage> = []

    var canSave: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hiddenGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var taskFormula: String {
        let audience = clean(audienceContext)
        let goal = clean(hiddenGoal)
        let success = clean(successCriterion)
        let obstacles = clean(barriers)
        let format = clean(solutionFormat)
        var result = "Помочь \(audience.isEmpty ? "читателю" : audience) \(goal.isEmpty ? "решить практическую задачу" : goal)"
        if !success.isEmpty { result += ", чтобы \(success)" }
        if !obstacles.isEmpty { result += ", учитывая \(obstacles)" }
        if !format.isEmpty { result += ", в формате: \(format)" }
        return result + "."
    }

    init(intent: ReaderIntent? = nil) {
        guard let intent else { return }
        query = intent.query
        audienceContext = intent.audienceContext
        hiddenGoal = intent.hiddenGoal
        successCriterion = intent.successCriterion
        barriers = intent.barriers
        solutionType = intent.solutionType
        solutionFormat = intent.solutionFormat
        coverage = intent.coverage
    }

    @MainActor
    func apply(to topic: Topic, source: ReaderIntentSource, in context: ModelContext) {
        guard canSave else { return }
        let intent: ReaderIntent
        if let saved = topic.readerIntent {
            intent = saved
        } else {
            intent = ReaderIntent(query: clean(query), hiddenGoal: clean(hiddenGoal))
            intent.topic = topic
            topic.readerIntent = intent
            context.insert(intent)
        }
        intent.query = clean(query)
        intent.audienceContext = clean(audienceContext)
        intent.hiddenGoal = clean(hiddenGoal)
        intent.successCriterion = clean(successCriterion)
        intent.barriers = clean(barriers)
        intent.solutionType = solutionType
        intent.solutionFormat = clean(solutionFormat)
        intent.coverage = coverage
        intent.source = source
        intent.semanticSnapshot = ReaderIntent.acceptedSemanticSnapshot(for: topic)
        intent.updatedAt = .now
        topic.updatedAt = .now
    }

    private func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
