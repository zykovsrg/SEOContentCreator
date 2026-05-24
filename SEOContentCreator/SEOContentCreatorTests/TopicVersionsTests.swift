import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct TopicVersionsTests {
    @Test func currentVersionResolvesByID() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self, GeneratedImage.self,
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
}
