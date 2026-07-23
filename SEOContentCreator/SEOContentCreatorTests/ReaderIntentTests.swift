import SwiftData
import Testing
@testable import SEOContentCreator

struct ReaderIntentTests {
    @Test func topicPersistsOptionalReaderIntent() throws {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, SemanticKeyword.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let topic = Topic(title: "Рак простаты", articleType: .disease)
        let intent = ReaderIntent(
            query: "рак простаты лечение",
            audienceContext: "Пациент после постановки диагноза",
            hiddenGoal: "Понять, какие варианты лечения обсудить с врачом",
            successCriterion: "Различает основные методы и ограничения",
            barriers: "Тревога и противоречивые советы",
            solutionType: .mixed,
            solutionFormat: "Сравнение + алгоритм",
            coverage: [.definition, .choiceComparison, .risksLimitations, .practicalSolution],
            source: .manual,
            semanticSnapshot: ["рак простаты лечение"]
        )
        context.insert(topic)
        context.insert(intent)
        topic.readerIntent = intent
        try context.save()
        #expect(topic.readerIntent?.hiddenGoal == "Понять, какие варианты лечения обсудить с врачом")
        #expect(intent.topic === topic)
    }

    @Test func oldTopicWithoutIntentRemainsValid() {
        #expect(Topic(title: "Тема", articleType: .info).readerIntent == nil)
    }

    @Test func snapshotUsesOnlyAcceptedAndRequiredQueries() {
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [
            SemanticKeyword(text: "  Бета  ", userDecision: .required),
            SemanticKeyword(text: "альфа", userDecision: .accepted),
            SemanticKeyword(text: "мусор", userDecision: .rejected)
        ]
        #expect(ReaderIntent.acceptedSemanticSnapshot(for: topic) == ["альфа", "бета"])
    }

    @Test func intentBecomesStaleAfterAcceptedSemanticsChange() {
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [SemanticKeyword(text: "первый", userDecision: .accepted)]
        let intent = ReaderIntent(query: "первый", hiddenGoal: "Получить ответ")
        intent.semanticSnapshot = ["первый"]
        #expect(intent.isStale(for: topic) == false)
        topic.semanticKeywords.append(SemanticKeyword(text: "второй", userDecision: .required))
        #expect(intent.isStale(for: topic) == true)
    }

    @Test func presentationStatusCoversMissingReadyAndStale() {
        let topic = Topic(title: "Тема", articleType: .info)
        #expect(ReaderIntentStatus.forTopic(topic) == .missing)
        let intent = ReaderIntent(query: "q", hiddenGoal: "понять решение")
        intent.semanticSnapshot = []
        topic.readerIntent = intent
        #expect(ReaderIntentStatus.forTopic(topic) == .ready(summary: "понять решение"))
        topic.semanticKeywords = [SemanticKeyword(text: "новый", userDecision: .accepted)]
        #expect(ReaderIntentStatus.forTopic(topic) == .stale(summary: "понять решение"))
    }
}
