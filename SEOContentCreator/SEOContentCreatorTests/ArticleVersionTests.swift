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

    @Test func versionStatusDefaultsToAcceptedForExistingBehavior() {
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        #expect(v.status == .accepted)
        #expect(v.isVisibleInVersionLane == true)
    }

    @Test func pendingRejectedAndArchivedStatusesAffectVisibility() {
        let pending = ArticleVersion(stage: .draft, source: .generated, text: "Черновик")
        pending.status = .pending
        #expect(pending.statusRaw == "pending")
        #expect(pending.isVisibleInVersionLane == false)

        pending.status = .rejected
        #expect(pending.statusRaw == "rejected")
        #expect(pending.isVisibleInVersionLane == false)

        pending.status = .archived
        #expect(pending.statusRaw == "archived")
        #expect(pending.isArchived == true)
        #expect(pending.isVisibleInVersionLane == false)
    }

    @Test func legacyArchivedFlagStillHidesVersion() {
        let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
        v.isArchived = true
        #expect(v.status == .archived)
        #expect(v.isVisibleInVersionLane == false)
    }
}
