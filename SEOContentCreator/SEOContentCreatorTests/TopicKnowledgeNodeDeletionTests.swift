import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

/// Regression test for a crash: deleting a KnowledgeNode referenced by
/// Topic.direction/doctor used to leave a dangling foreign key, which made
/// SwiftData crash while resolving the fault on next launch (ContentPlanView
/// reading `direction?.title`). See ai/changelog.md 2026-07-03.
struct TopicKnowledgeNodeDeletionTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self, GeneratedImage.self, ExternalDocument.self,
                 SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func deletingDirectionNodeNullifiesTopicReference() throws {
        let context = try makeContext()
        let direction = KnowledgeNode(title: "Урология", type: .direction)
        context.insert(direction)
        let topic = Topic(title: "Тест", articleType: .disease, direction: direction)
        context.insert(topic)
        try context.save()

        context.delete(direction)
        try context.save()

        #expect(topic.direction == nil)
    }

    @Test func deletingDoctorNodeNullifiesTopicReference() throws {
        let context = try makeContext()
        let doctor = KnowledgeNode(title: "Врач", type: .doctor)
        context.insert(doctor)
        let topic = Topic(title: "Тест", articleType: .disease, doctor: doctor)
        context.insert(topic)
        try context.save()

        context.delete(doctor)
        try context.save()

        #expect(topic.doctor == nil)
    }
}
