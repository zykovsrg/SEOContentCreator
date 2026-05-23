import Testing
import Foundation
@testable import SEOContentCreator

struct StageTemplateDefaultsTests {
    @Test func hasContentForEveryStage() {
        for stage in PipelineStage.allCases {
            let c = StageTemplateDefaults.content(for: stage)
            #expect(!c.userPromptTemplate.isEmpty)
            #expect(c.modelName == "gpt-4.1")
            #expect(c.temperature == 0.6)
            #expect(c.maxTokens == 8000)
        }
    }

    @Test func authorDraftUsesBriefVariables() {
        #expect(StageTemplateDefaults.content(for: .draft).userPromptTemplate.contains("{{тема}}"))
    }

    @Test func checkingStagesAskForRemarksJSON() {
        #expect(StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate.contains("remarks"))
        #expect(StageTemplateDefaults.content(for: .factCheck).userPromptTemplate.contains("{{база_знаний}}"))
        #expect(StageTemplateDefaults.content(for: .finalReview).userPromptTemplate.contains("remarks"))
    }

    @Test func systemPromptsDoNotContainRoleMethodics() {
        for stage in PipelineStage.allCases {
            let system = StageTemplateDefaults.content(for: stage).systemPrompt
            #expect(!system.contains("Ты —"))
            #expect(!system.localizedCaseInsensitiveContains("markdown"))
            #expect(!system.localizedCaseInsensitiveContains("не выдум"))
            #expect(!system.localizedCaseInsensitiveContains("доказатель"))
            #expect(!system.localizedCaseInsensitiveContains("русск"))
        }
    }
}
