import Foundation
import SwiftData

/// A single suggestion from the "Анализ и обучение" stage (FT-20260703-003):
/// a recurring problem in the generated text and a proposed edit to the prompt
/// system that would fix it. Shown for manual review only — never auto-applied.
@Model
final class PromptRecommendation {
    var uuid: UUID
    var problem: String
    var location: String
    var suggestion: String
    var createdAt: Date

    @Relationship var topic: Topic?
    @Relationship var job: GenerationJob?

    init(problem: String, location: String, suggestion: String) {
        self.uuid = UUID()
        self.problem = problem
        self.location = location
        self.suggestion = suggestion
        self.createdAt = .now
    }
}
