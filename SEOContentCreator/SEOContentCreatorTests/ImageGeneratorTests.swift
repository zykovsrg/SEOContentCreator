import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImageGeneratorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, PromptRecommendation.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, PersistedRemark.self, StageTemplate.self,
                 ContextBlock.self, AIRole.self,
                 GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
                 ExternalDocument.self, SemanticKeyword.self, PublishedSitePage.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func cannedImage(_ bytes: Data) -> ImageGenerator.ImageProvider {
        { _, _, _, _, _, _ in bytes }
    }

    @Test func successSetsPreviewAndLogsJob() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let gen = ImageGenerator(imageProvider: cannedImage(Data([7, 8, 9])),
                                 keyProvider: { "k" }, model: "gpt-image-1")

        await gen.render(topic: topic, prompt: "p", size: "1024x1024", quality: "high",
                         references: [], in: context)

        #expect(gen.isRunning == false)
        #expect(gen.previewData == Data([7, 8, 9]))
        #expect(gen.lastErrorMessage == nil)
        #expect(topic.jobs.first?.status == .success)
        #expect(topic.jobs.first?.stageTitle == "Изображение")
    }

    @Test func missingKeyProducesErrorJobNoPreview() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let gen = ImageGenerator(imageProvider: cannedImage(Data([1])),
                                 keyProvider: { throw KeychainService.KeychainError.notFound },
                                 model: "m")

        await gen.render(topic: topic, prompt: "p", size: "1024x1024", quality: "high",
                         references: [], in: context)

        #expect(gen.previewData == nil)
        #expect(topic.jobs.first?.status == .error)
        #expect(gen.lastErrorMessage == "Укажите API-ключ в Настройках")
    }

    @Test func apiErrorProducesErrorJob() async throws {
        let context = try makeContext()
        let topic = Topic(title: "Тема", articleType: .disease)
        context.insert(topic)
        let failing: ImageGenerator.ImageProvider = { _, _, _, _, _, _ in
            throw OpenAIClient.OpenAIError.rateLimited
        }
        let gen = ImageGenerator(imageProvider: failing, keyProvider: { "k" }, model: "m")

        await gen.render(topic: topic, prompt: "p", size: "1024x1024", quality: "high",
                         references: [], in: context)

        #expect(gen.previewData == nil)
        #expect(topic.jobs.first?.status == .error)
        #expect(gen.lastErrorMessage != nil)
    }
}
