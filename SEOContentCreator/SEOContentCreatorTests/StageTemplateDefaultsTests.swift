import Testing
import Foundation
@testable import SEOContentCreator

struct StageTemplateDefaultsTests {
    @Test func hasContentForEveryStage() {
        for stage in PipelineStage.allCases where stage.kind != .action {
            let c = StageTemplateDefaults.content(for: stage)
            #expect(!c.userPromptTemplate.isEmpty)
            guard stage != .finalReview else { continue }
            #expect(c.modelName == "gpt-4.1")
            #expect(c.maxTokens == 8000)
        }
    }

    @Test func finalReviewUsesReasoningModel() {
        let c = StageTemplateDefaults.content(for: .finalReview)
        #expect(c.modelName == "gpt-5.5")
        #expect(c.maxTokens == 11000)
        #expect(c.reasoningEffort == "high")
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

    @Test func structureStageIsPlanOnlyWithoutStructureVariable() {
        let c = StageTemplateDefaults.content(for: .structure)
        #expect(c.userPromptTemplate.contains("{{тема}}"))
        #expect(c.userPromptTemplate.contains("H1"))
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

    @Test func promptAnalysisAsksForRecommendationsJSONWithStageContext() {
        let c = StageTemplateDefaults.content(for: .promptAnalysis)
        #expect(c.userPromptTemplate.contains("{{история_версий_по_этапам}}"))
        #expect(c.userPromptTemplate.contains("{{текущие_промты_этапов}}"))
        #expect(c.userPromptTemplate.contains("recommendations"))
        #expect(c.temperature == 0.3)
    }

    @Test func readerIntentAppearsOnlyInRelevantStages() {
        let included: Set<PipelineStage> = [.structure, .draft, .semanticsInText, .seoCheck]
        for stage in PipelineStage.allCases where stage.kind != .action {
            let prompt = StageTemplateDefaults.content(for: stage).userPromptTemplate
            let contains = prompt.contains("{{задача_читателя}}")
            #expect(contains == included.contains(stage))
            if included.contains(stage) {
                #expect(prompt.contains("<!-- reader-intent-v1:\(stage.rawValue) -->"))
            }
        }
    }

    @Test func structureUsesSemanticsAsOrientationNotMandatoryKeys() {
        let prompt = StageTemplateDefaults.content(for: .structure).userPromptTemplate
        #expect(prompt.contains("{{семантика}}"))
        #expect(prompt.contains("ориентир"))
        #expect(prompt.contains("не список обязательных"))
        #expect(!prompt.contains("блок «Полезное действие»"))
    }

    @Test func seoCheckAddsIntentAndCompletenessCategories() {
        let prompt = StageTemplateDefaults.content(for: .seoCheck).userPromptTemplate
        #expect(prompt.contains("«Интент»"))
        #expect(prompt.contains("«Полнота»"))
    }
}
