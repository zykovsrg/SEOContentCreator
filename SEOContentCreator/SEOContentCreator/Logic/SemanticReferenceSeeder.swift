import Foundation
import SwiftData

enum SemanticStopWordDefaults {
    /// Academic and student queries that look relevant but never convert.
    static let all: [String] = [
        "реферат", "курсовая", "диссертация", "презентация", "лекция",
        "конспект", "шпаргалка", "тест", "задача", "учебник",
        "патогенез", "этиология", "классификация", "мкб", "гистология"
    ]
}

enum SemanticQueryMaskDefaults {
    /// Question words from the semantic-core methodology.
    static let all: [String] = [
        "как", "где", "зачем", "что", "сколько", "почему", "куда",
        "кто", "чей", "когда", "какой", "какая", "какое", "какие", "который"
    ]
}

enum SemanticReferenceSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existingWords = (try? context.fetch(FetchDescriptor<SemanticStopWord>())) ?? []
        if existingWords.isEmpty {
            for (index, text) in SemanticStopWordDefaults.all.enumerated() {
                context.insert(SemanticStopWord(text: text, order: index))
            }
        }

        let existingMasks = (try? context.fetch(FetchDescriptor<SemanticQueryMask>())) ?? []
        if existingMasks.isEmpty {
            for (index, text) in SemanticQueryMaskDefaults.all.enumerated() {
                context.insert(SemanticQueryMask(text: text, order: index))
            }
        }
    }
}
