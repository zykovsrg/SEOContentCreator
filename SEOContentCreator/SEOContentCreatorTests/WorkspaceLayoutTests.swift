import Testing
@testable import SEOContentCreator

struct WorkspaceLayoutTests {
    @Test func idleAuthorStageStaysSingleColumn() {
        #expect(WorkspaceLayout.isComparing(stageKind: .author, isRunning: false, hasPendingVersion: false) == false)
    }

    @Test func runningAuthorStageComparesColumns() {
        #expect(WorkspaceLayout.isComparing(stageKind: .author, isRunning: true, hasPendingVersion: false) == true)
    }

    @Test func pendingVersionComparesColumns() {
        #expect(WorkspaceLayout.isComparing(stageKind: .author, isRunning: false, hasPendingVersion: true) == true)
    }

    @Test func checkingStageNeverCompares() {
        #expect(WorkspaceLayout.isComparing(stageKind: .checking, isRunning: true, hasPendingVersion: false) == false)
        #expect(WorkspaceLayout.isComparing(stageKind: .checking, isRunning: false, hasPendingVersion: false) == false)
    }

    @Test func actionStageFollowsSameRules() {
        #expect(WorkspaceLayout.isComparing(stageKind: .action, isRunning: true, hasPendingVersion: false) == true)
        #expect(WorkspaceLayout.isComparing(stageKind: .action, isRunning: false, hasPendingVersion: false) == false)
    }
}
