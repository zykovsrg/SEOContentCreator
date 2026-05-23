import Testing
@testable import SEOContentCreator

struct PipelineStageTests {
    @Test func authorStagesHaveAuthorAgent() {
        #expect(PipelineStage.draft.agentName == "ИИ-автор")
        #expect(PipelineStage.productBlocks.agentName == "ИИ-автор")
        #expect(PipelineStage.semanticsInText.agentName == "ИИ-автор")
    }

    @Test func titlesAreRussian() {
        #expect(PipelineStage.draft.title == "Черновик")
        #expect(PipelineStage.semanticsInText.title == "Семантика-в-текст")
    }

    @Test func allCasesRoundTripViaRawValue() {
        for stage in PipelineStage.allCases {
            #expect(PipelineStage(rawValue: stage.rawValue) == stage)
        }
    }

    @Test func checkingStagesHaveOwnAgents() {
        #expect(PipelineStage.seoCheck.agentName == "ИИ-SEO")
        #expect(PipelineStage.factCheck.agentName == "ИИ-фактчекер")
        #expect(PipelineStage.finalReview.agentName == "ИИ-редактор")
    }

    @Test func stageKindIsClassified() {
        #expect(PipelineStage.draft.kind == .author)
        #expect(PipelineStage.semanticsInText.kind == .author)
        #expect(PipelineStage.seoCheck.kind == .checking)
        #expect(PipelineStage.finalReview.kind == .checking)
    }

    @Test func checkingTitlesAreRussian() {
        #expect(PipelineStage.seoCheck.title == "Проверка SEO")
        #expect(PipelineStage.factCheck.title == "Фактчекинг")
        #expect(PipelineStage.finalReview.title == "Финальная вычитка")
    }

    @Test func roleKeysAreAssignedForEveryStage() {
        #expect(PipelineStage.draft.roleKey == "author")
        #expect(PipelineStage.productBlocks.roleKey == "author")
        #expect(PipelineStage.semanticsInText.roleKey == "author")
        #expect(PipelineStage.seoCheck.roleKey == "seo")
        #expect(PipelineStage.factCheck.roleKey == "factChecker")
        #expect(PipelineStage.finalReview.roleKey == "editor")
    }
}
