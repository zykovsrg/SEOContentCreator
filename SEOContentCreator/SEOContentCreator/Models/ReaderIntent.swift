import Foundation
import SwiftData

enum ReaderIntentSolutionType: String, Codable, CaseIterable, Identifiable {
    case explanation, algorithm, comparison, directOffer, mixed
    var id: String { rawValue }
}

enum ReaderIntentCoverage: String, Codable, CaseIterable, Identifiable {
    case definition, currentRelevance, choiceComparison, evidence
    case socialProof, applicationContext, risksLimitations, practicalSolution
    var id: String { rawValue }
}

enum ReaderIntentSource: String, Codable { case manual, ai }

@Model
final class ReaderIntent {
    var uuid: UUID
    var query: String
    var audienceContext: String
    var hiddenGoal: String
    var successCriterion: String
    var barriers: String
    var solutionTypeRaw: String
    var solutionFormat: String
    var coverageRaw: [String]
    var sourceRaw: String
    var semanticSnapshot: [String]
    var createdAt: Date
    var updatedAt: Date
    var topic: Topic?

    init(
        query: String,
        audienceContext: String = "",
        hiddenGoal: String,
        successCriterion: String = "",
        barriers: String = "",
        solutionType: ReaderIntentSolutionType = .explanation,
        solutionFormat: String = "",
        coverage: Set<ReaderIntentCoverage> = [],
        source: ReaderIntentSource = .manual,
        semanticSnapshot: [String] = []
    ) {
        self.uuid = UUID()
        self.query = query
        self.audienceContext = audienceContext
        self.hiddenGoal = hiddenGoal
        self.successCriterion = successCriterion
        self.barriers = barriers
        self.solutionTypeRaw = solutionType.rawValue
        self.solutionFormat = solutionFormat
        self.coverageRaw = coverage.map(\.rawValue).sorted()
        self.sourceRaw = source.rawValue
        self.semanticSnapshot = Self.normalize(semanticSnapshot)
        self.createdAt = .now
        self.updatedAt = .now
    }

    var solutionType: ReaderIntentSolutionType {
        get { ReaderIntentSolutionType(rawValue: solutionTypeRaw) ?? .explanation }
        set { solutionTypeRaw = newValue.rawValue; updatedAt = .now }
    }

    var coverage: Set<ReaderIntentCoverage> {
        get { Set(coverageRaw.compactMap(ReaderIntentCoverage.init(rawValue:))) }
        set { coverageRaw = newValue.map(\.rawValue).sorted(); updatedAt = .now }
    }

    var source: ReaderIntentSource {
        get { ReaderIntentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue; updatedAt = .now }
    }

    var taskFormula: String {
        Self.taskFormula(
            audienceContext: audienceContext,
            hiddenGoal: hiddenGoal,
            successCriterion: successCriterion,
            barriers: barriers,
            solutionFormat: solutionFormat
        )
    }

    /// A readable, labelled summary of the brief. Fields are free text — the user or the
    /// "Обновить с ИИ" pass often fills them with whole sentences — so instead of splicing
    /// them into one flowing phrase (which broke on their punctuation and capitalisation),
    /// each non-empty field becomes its own labelled clause, robust to any phrasing.
    /// Display-only: the prompt fed to the AI stages uses `ReaderIntentPromptRenderer`.
    static func taskFormula(
        audienceContext: String,
        hiddenGoal: String,
        successCriterion: String,
        barriers: String,
        solutionFormat: String
    ) -> String {
        var parts: [String] = []
        func add(_ label: String, _ raw: String) {
            let value = clean(raw)
            guard !value.isEmpty else { return }
            parts.append("\(label): \(terminate(value))")
        }
        add("Кому", audienceContext)
        let goal = clean(hiddenGoal)
        add("Задача", goal.isEmpty ? "решить практическую задачу" : goal)
        add("Польза", successCriterion)
        add("Барьеры", barriers)
        add("Формат", solutionFormat)
        return parts.joined(separator: " ")
    }

    /// Ensures a clause ends with exactly one sentence terminator, so a labelled part
    /// reads cleanly whether the field was a whole sentence or a bare fragment: keep an
    /// existing `. ! ? …`, turn a trailing `, ; :` into `.`, otherwise append `.`.
    private static func terminate(_ value: String) -> String {
        guard let last = value.last else { return value }
        if ".!?…".contains(last) { return value }
        if ",;:".contains(last) { return String(value.dropLast()) + "." }
        return value + "."
    }

    func isStale(for topic: Topic) -> Bool {
        Self.normalize(semanticSnapshot) != Self.acceptedSemanticSnapshot(for: topic)
    }

    static func acceptedSemanticSnapshot(for topic: Topic) -> [String] {
        Array(Set(topic.semanticKeywords.compactMap { keyword in
            guard keyword.userDecision == .accepted || keyword.userDecision == .required else { return nil }
            let normalized = clean(keyword.text).lowercased()
            return normalized.isEmpty ? nil : normalized
        })).sorted()
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalize(_ values: [String]) -> [String] {
        Array(Set(values.map { clean($0).lowercased() }.filter { !$0.isEmpty })).sorted()
    }
}

enum ReaderIntentStatus: Equatable {
    case missing
    case ready(summary: String)
    case stale(summary: String)

    static func forTopic(_ topic: Topic) -> ReaderIntentStatus {
        guard let intent = topic.readerIntent else { return .missing }
        let summary = intent.hiddenGoal
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return intent.isStale(for: topic) ? .stale(summary: summary) : .ready(summary: summary)
    }
}
