import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct VersionActionsTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, ReaderIntent.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self, GeneratedImage.self, ExternalDocument.self,
                 SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func applyManualEditCreatesNewCurrentVersion() throws {
        let context = try makeContext()
        let topic = Topic(title: "Тест", articleType: .disease)
        context.insert(topic)
        let original = ArticleVersion(stage: .draft, source: .generated, text: "Старый текст")
        original.topic = topic
        context.insert(original)
        topic.currentVersionID = original.uuid

        let version = VersionActions.applyManualEdit(topic: topic, newText: "Новый текст", in: context)

        #expect(version.text == "Новый текст")
        #expect(version.source == .manualEdit)
        #expect(version.stageTitle == "Ручная правка")
        #expect(topic.currentVersionID == version.uuid)
        #expect(topic.currentVersion?.text == "Новый текст")
        #expect(topic.versions.count == 2)
    }

    @Test func acceptsSelectedNewParagraphsKeepsRestFromOld() {
        let old = "A\n\nB\n\nC"
        let new = "A2\n\nB2\n\nC2"
        // accept only paragraphs at index 0 and 2 from new; index 1 stays old
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 2])
        #expect(hybrid == "A2\n\nB\n\nC2")
    }

    @Test func emptySelectionReturnsOld() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [])
        #expect(hybrid == "A\n\nB")
    }

    @Test func fullSelectionReturnsNew() {
        let old = "A\n\nB"
        let new = "X\n\nY"
        let hybrid = VersionActions.assembleHybrid(old: old, new: new, acceptedNewIndices: [0, 1])
        #expect(hybrid == "X\n\nY")
    }
}
