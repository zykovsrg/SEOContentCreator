import Foundation

/// Decides whether the topic workspace should show the two-column comparison
/// layout (current version vs. new version) or a single full-width column.
///
/// Checking stages (SEO/факт/финальная вычитка) never produce a new article
/// version to compare against — they only ever yield remarks (handled by the
/// separate review UI) or a "no remarks" result — so they always stay
/// single-column, even while running.
enum WorkspaceLayout {
    static func isComparing(stageKind: StageKind, isRunning: Bool, hasPendingVersion: Bool) -> Bool {
        guard stageKind != .checking else { return false }
        return isRunning || hasPendingVersion
    }
}
