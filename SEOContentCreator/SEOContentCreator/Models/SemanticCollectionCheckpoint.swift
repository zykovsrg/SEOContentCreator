import Foundation
import SwiftData

/// Resumable progress for one in-flight `SemanticCollectionRunner.run` call.
/// One per `Topic`. Deleted when the run finishes successfully, or explicitly
/// via `SemanticCollectionRunner.resetCheckpoint`.
@Model
final class SemanticCollectionCheckpoint {
    var uuid: UUID
    var runID: UUID
    /// Full seed-phrase plan, computed once by the AI planner and never
    /// recomputed while this checkpoint exists.
    var seeds: [String]
    /// Seeds already pulled from Wordstat successfully.
    var completedSeeds: [String]
    /// Wordstat results accumulated so far, across every completed seed.
    var pulled: [WordstatPhrase]
    /// Settings frozen at the first attempt; later edits to stop-words/masks/
    /// threshold/limit only apply to a fresh run, not a resumed one.
    var stopWordsSnapshot: [String]
    var masksSnapshot: [String]
    var thresholdSnapshot: Int
    var limitSnapshot: Int
    var createdAt: Date
    var updatedAt: Date

    var topic: Topic?

    init(
        runID: UUID,
        seeds: [String],
        stopWords: [String],
        masks: [String],
        threshold: Int,
        limit: Int
    ) {
        self.uuid = UUID()
        self.runID = runID
        self.seeds = seeds
        self.completedSeeds = []
        self.pulled = []
        self.stopWordsSnapshot = stopWords
        self.masksSnapshot = masks
        self.thresholdSnapshot = threshold
        self.limitSnapshot = limit
        self.createdAt = .now
        self.updatedAt = .now
    }
}
