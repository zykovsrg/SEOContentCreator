import Testing
import Foundation
@testable import SEOContentCreator

struct ArticleVersionTests {
    @Test func generatedVersionExposesStageAndSource() {
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст", agentName: "ИИ-автор")
        #expect(v.stageRaw == "draft")
        #expect(v.source == .generated)
        #expect(v.stageTitle == "Черновик")
        #expect(v.isArchived == false)
        #expect(v.uuid != ArticleVersion(stage: .draft, source: .generated, text: "x").uuid)
    }

    @Test func manualEditVersionHasReadableTitle() {
        let v = ArticleVersion(stageLabel: "manualEdit", source: .manualEdit, text: "Текст")
        #expect(v.stageTitle == "Ручная правка")
    }
}
