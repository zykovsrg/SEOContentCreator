import Testing
@testable import SEOContentCreator

struct StageProgressTests {
    @Test func stageWithAcceptedVersionIsCompleted() {
        let draft = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        #expect(StageProgress.isCompleted(.draft, versions: [draft]) == true)
    }

    @Test func stageWithoutVersionIsNotCompleted() {
        let draft = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        #expect(StageProgress.isCompleted(.seoCheck, versions: [draft]) == false)
    }

    @Test func pendingOrRejectedVersionDoesNotCountAsCompleted() {
        let pending = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        pending.status = .pending
        #expect(StageProgress.isCompleted(.draft, versions: [pending]) == false)

        let rejected = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        rejected.status = .rejected
        #expect(StageProgress.isCompleted(.draft, versions: [rejected]) == false)
    }

    @Test func manualEditVersionDoesNotCountForAnyPipelineStage() {
        let manual = ArticleVersion(stageLabel: "manualEdit", source: .manualEdit, text: "Текст")
        for stage in PipelineStage.allCases {
            #expect(StageProgress.isCompleted(stage, versions: [manual]) == false)
        }
    }

    @Test func structureStageIsCompletedWhenStructureTextIsSaved() {
        #expect(StageProgress.isCompleted(.structure, versions: [], structureText: "H1: Заголовок") == true)
    }

    @Test func structureStageIsNotCompletedWithoutStructureText() {
        #expect(StageProgress.isCompleted(.structure, versions: [], structureText: "") == false)
        #expect(StageProgress.isCompleted(.structure, versions: [], structureText: "   \n") == false)
    }

    @Test func structureStageIgnoresVersionsEvenIfPresent() {
        let draft = ArticleVersion(stage: .structure, source: .generated, text: "Текст")
        #expect(StageProgress.isCompleted(.structure, versions: [draft], structureText: "") == false)
    }

    @Test func imagesStageCompletionFollowsHasImagesFlag() {
        #expect(StageProgress.isCompleted(.images, versions: [], hasImages: false) == false)
        #expect(StageProgress.isCompleted(.images, versions: [], hasImages: true) == true)
    }
}
