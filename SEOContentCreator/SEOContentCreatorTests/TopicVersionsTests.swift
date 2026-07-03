import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct TopicVersionsTests {
    @Test func currentVersionResolvesByID() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self, GeneratedImage.self, ExternalDocument.self,
                 SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        let context = ModelContext(container)

        let topic = Topic(title: "Тест", articleType: .disease)
        context.insert(topic)
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Черновик")
        v.topic = topic
        context.insert(v)
        topic.currentVersionID = v.uuid

        #expect(topic.currentVersion?.uuid == v.uuid)
        #expect(topic.semantics.isEmpty)
    }

    @Test func currentVersionNilWhenUnset() {
        let topic = Topic(title: "Тест", articleType: .disease)
        #expect(topic.currentVersion == nil)
    }

    @Test func totalTokenCostSumsPromptAndCompletionAcrossJobs() {
        let topic = Topic(title: "Тест", articleType: .disease)
        let jobA = GenerationJob(stage: .draft, agentName: "Автор", modelName: "gpt-4.1")
        jobA.promptTokens = 100
        jobA.completionTokens = 50
        let jobB = GenerationJob(stage: .seoCheck, agentName: "SEO", modelName: "gpt-4.1")
        jobB.promptTokens = 30
        jobB.completionTokens = 10
        topic.jobs = [jobA, jobB]

        #expect(topic.totalTokenCost == 190)
    }

    @Test func totalTokenCostTreatsMissingUsageAsZero() {
        let topic = Topic(title: "Тест", articleType: .disease)
        let job = GenerationJob(stage: .draft, agentName: "Автор", modelName: "gpt-4.1")
        // promptTokens/completionTokens left nil, as for jobs that predate FT-20260702-005.
        topic.jobs = [job]

        #expect(topic.totalTokenCost == 0)
    }
}
