import SwiftData
import Testing
@testable import SEOContentCreator

@MainActor
struct ReaderIntentAnalysisTests {
    @Test func parsesStrictJSONIntoDraft() throws {
        let json = #"{"query":"рак простаты","audienceContext":"пациент","hiddenGoal":"выбрать тактику","successCriterion":"понимает варианты","barriers":"тревога","solutionType":"mixed","solutionFormat":"сравнение","coverage":["definition","risksLimitations"]}"#
        let draft = try ReaderIntentResponseParser.parse(json)
        #expect(draft.solutionType == .mixed)
        #expect(draft.coverage == [.definition, .risksLimitations])
    }

    @Test func rejectsUnknownCoverage() {
        let json = #"{"query":"q","audienceContext":"","hiddenGoal":"g","successCriterion":"","barriers":"","solutionType":"explanation","solutionFormat":"","coverage":["unknown"]}"#
        #expect(throws: ReaderIntentResponseParser.ParserError.badResponse) {
            try ReaderIntentResponseParser.parse(json)
        }
    }

    @Test func rendererOmitsEmptyLinesAndHasEmptyFallback() {
        let topic = Topic(title: "Тема", articleType: .info)
        #expect(ReaderIntentPromptRenderer.render(topic: topic) == "Карта задачи читателя не заполнена.")
        let intent = ReaderIntent(query: "запрос", hiddenGoal: "получить решение")
        intent.coverage = [.practicalSolution]
        topic.readerIntent = intent
        let rendered = ReaderIntentPromptRenderer.render(topic: topic)
        #expect(rendered.contains("- Запрос: запрос"))
        #expect(rendered.contains("- Практическая задача: получить решение"))
        #expect(!rendered.contains("Барьеры и сомнения:"))
    }

    @Test func analyzerSendsOnlyAcceptedAndRequiredSemantics() async throws {
        var capturedUser = ""
        let analyzer = ReaderIntentAnalyzer(
            streamProvider: { _, _, user, _, _, _, _ in
                capturedUser = user
                return AsyncThrowingStream { continuation in
                    continuation.yield(.token(#"{"query":"q","audienceContext":"","hiddenGoal":"g","successCriterion":"","barriers":"","solutionType":"explanation","solutionFormat":"","coverage":[]}"#))
                    continuation.finish()
                }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        let topic = Topic(title: "Тема", articleType: .info)
        topic.direction = KnowledgeNode(title: "Онкология", type: .direction, content: "Профиль направления", sources: ["https://example.test/source"])
        topic.doctor = KnowledgeNode(title: "Доктор", type: .doctor, content: "Опыт врача")
        topic.attachedNodes = [KnowledgeNode(title: "Преимущество", type: .advantage, content: "Консилиум")]
        topic.semanticKeywords = [
            SemanticKeyword(text: "принятый", userDecision: .accepted),
            SemanticKeyword(text: "обязательный", userDecision: .required),
            SemanticKeyword(text: "отклонённый", userDecision: .rejected)
        ]
        _ = try await analyzer.analyze(topic: topic)
        #expect(capturedUser.contains("принятый"))
        #expect(capturedUser.contains("обязательный"))
        #expect(!capturedUser.contains("отклонённый"))
        #expect(capturedUser.contains("Профиль направления"))
        #expect(capturedUser.contains("Опыт врача"))
        #expect(capturedUser.contains("Консилиум"))
        #expect(capturedUser.contains("https://example.test/source"))
    }

    @Test func analyzerRejectsEmptyResponse() async {
        let analyzer = ReaderIntentAnalyzer(
            streamProvider: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { $0.finish() }
            },
            keyProvider: { "sk-test" },
            model: "gpt-4.1"
        )
        await #expect(throws: ReaderIntentAnalyzer.AnalyzerError.emptyResponse) {
            try await analyzer.analyze(topic: Topic(title: "Тема", articleType: .info))
        }
    }

    @Test func applyingDraftCapturesCurrentSemanticSnapshot() throws {
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, KnowledgeNode.self, SemanticKeyword.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        topic.semanticKeywords = [SemanticKeyword(text: "  Принятый запрос ", userDecision: .accepted)]
        context.insert(topic)
        var draft = ReaderIntentDraft()
        draft.query = " запрос "
        draft.hiddenGoal = " получить ответ "
        draft.apply(to: topic, source: .manual, in: context)
        #expect(topic.readerIntent?.query == "запрос")
        #expect(topic.readerIntent?.semanticSnapshot == ["принятый запрос"])
        #expect(topic.readerIntent?.source == .manual)
    }
}
