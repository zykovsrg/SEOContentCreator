import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct StageTemplateSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
                 GenerationJob.self, StageTemplate.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func seedsOneTemplatePerStage() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
        for stage in PipelineStage.allCases {
            #expect(all.contains { $0.stageRaw == stage.rawValue })
        }
    }

    @Test func seedingIsIdempotent() throws {
        let context = try makeContext()
        StageTemplateSeeder.seedIfNeeded(in: context)
        StageTemplateSeeder.seedIfNeeded(in: context)
        let all = try context.fetch(FetchDescriptor<StageTemplate>())
        #expect(all.count == PipelineStage.allCases.count)
    }
}
