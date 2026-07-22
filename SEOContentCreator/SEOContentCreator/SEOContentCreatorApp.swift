import SwiftUI
import SwiftData

@main
struct SEOContentCreatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Topic.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self,
            SemanticKeyword.self, PublishedSitePage.self,
            ProductBlock.self, ForbiddenPhrase.self,
            PersistedRemark.self, PromptRecommendation.self,
            SemanticStopWord.self, SemanticQueryMask.self, SemanticFunnelEntry.self
        ])

        Settings {
            SettingsView()
        }
    }
}
