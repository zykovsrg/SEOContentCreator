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
}
