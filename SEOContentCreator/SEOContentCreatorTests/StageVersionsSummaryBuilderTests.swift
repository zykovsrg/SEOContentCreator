import Testing
import Foundation
@testable import SEOContentCreator

struct StageVersionsSummaryBuilderTests {
    @Test func includesStructureTextWhenPresent() {
        let topic = Topic(title: "Тема", articleType: .disease)
        topic.structureText = "# H1\n## Введение"
        let summary = StageVersionsSummaryBuilder.build(topic: topic)
        #expect(summary.contains("Структура"))
        #expect(summary.contains("# H1\n## Введение"))
    }

    @Test func omitsStructureWhenEmpty() {
        let topic = Topic(title: "Тема", articleType: .disease)
        let summary = StageVersionsSummaryBuilder.build(topic: topic)
        #expect(!summary.contains("Структура"))
    }

    @Test func includesOnlyLatestAcceptedVersionPerStage() {
        let topic = Topic(title: "Тема", articleType: .disease)
        let old = ArticleVersion(stage: .draft, source: .generated, text: "Старый текст")
        old.status = .accepted
        let newer = ArticleVersion(stage: .draft, source: .generated, text: "Новый текст")
        newer.status = .accepted
        newer.createdAt = old.createdAt.addingTimeInterval(60)
        topic.versions = [old, newer]

        let summary = StageVersionsSummaryBuilder.build(topic: topic)

        #expect(summary.contains("Новый текст"))
        #expect(!summary.contains("Старый текст"))
    }

    @Test func skipsPendingAndRejectedVersions() {
        let topic = Topic(title: "Тема", articleType: .disease)
        let pending = ArticleVersion(stage: .draft, source: .generated, text: "Ожидает решения")
        pending.status = .pending
        topic.versions = [pending]

        let summary = StageVersionsSummaryBuilder.build(topic: topic)

        #expect(!summary.contains("Ожидает решения"))
    }

    @Test func skipsImagesAndPromptAnalysisStages() {
        let topic = Topic(title: "Тема", articleType: .disease)
        // Neither stage ever produces an ArticleVersion in practice, but guard the builder anyway.
        let stray = ArticleVersion(stageLabel: PipelineStage.images.rawValue, source: .generated, text: "Не должно попасть")
        stray.status = .accepted
        topic.versions = [stray]

        let summary = StageVersionsSummaryBuilder.build(topic: topic)

        #expect(!summary.contains("Не должно попасть"))
    }
}
