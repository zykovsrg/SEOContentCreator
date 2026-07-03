import Testing
import Foundation
@testable import SEOContentCreator

struct StageTemplateDefaultsTests {
    @Test func hasContentForEveryStage() {
        for stage in PipelineStage.allCases where stage.kind != .action {
            let c = StageTemplateDefaults.content(for: stage)
            #expect(!c.userPromptTemplate.isEmpty)
            #expect(c.modelName == "gpt-4.1")
            #expect(c.maxTokens == 8000)
        }
    }

    @Test func checkingStagesUseLowerTemperature() {
        for stage in PipelineStage.allCases where stage.kind == .checking {
            #expect(StageTemplateDefaults.content(for: stage).temperature == 0.3)
        }
    }

    @Test func authorStagesKeepDefaultTemperature() {
        for stage in PipelineStage.allCases where stage.kind == .author {
            #expect(StageTemplateDefaults.content(for: stage).temperature == 0.6)
        }
    }

    @Test func authorDraftUsesBriefVariables() {
        #expect(StageTemplateDefaults.content(for: .draft).userPromptTemplate.contains("{{тема}}"))
    }

    @Test func draftUsesStructureVariable() {
        #expect(StageTemplateDefaults.content(for: .draft).userPromptTemplate.contains("{{структура}}"))
    }

    @Test func structureStageIsPlanOnlyWithoutKeywords() {
        let c = StageTemplateDefaults.content(for: .structure)
        #expect(c.userPromptTemplate.contains("{{тема}}"))
        #expect(c.userPromptTemplate.contains("H1"))
        #expect(!c.userPromptTemplate.contains("{{семантика}}"))
        #expect(!c.userPromptTemplate.contains("{{структура}}"))
    }

    @Test func checkingStagesAskForRemarksJSON() {
        #expect(StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate.contains("remarks"))
        #expect(StageTemplateDefaults.content(for: .factCheck).userPromptTemplate.contains("{{база_знаний}}"))
        #expect(StageTemplateDefaults.content(for: .finalReview).userPromptTemplate.contains("remarks"))
    }

    @Test func seoCheckSeesCurrentH1TitleDescription() {
        let c = StageTemplateDefaults.content(for: .seoCheck)
        #expect(c.userPromptTemplate.contains("{{текущий_h1}}"))
        #expect(c.userPromptTemplate.contains("{{текущий_title}}"))
        #expect(c.userPromptTemplate.contains("{{текущий_description}}"))
    }

    @Test func systemPromptsDoNotContainRoleMethodics() {
        for stage in PipelineStage.allCases where stage.kind != .action {
            let system = StageTemplateDefaults.content(for: stage).systemPrompt
            #expect(!system.contains("Ты —"))
            #expect(!system.localizedCaseInsensitiveContains("markdown"))
            #expect(!system.localizedCaseInsensitiveContains("не выдум"))
            #expect(!system.localizedCaseInsensitiveContains("доказатель"))
            #expect(!system.localizedCaseInsensitiveContains("русск"))
        }
    }
}
