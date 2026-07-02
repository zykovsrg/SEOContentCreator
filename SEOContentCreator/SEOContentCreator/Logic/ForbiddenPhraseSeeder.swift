import Foundation
import SwiftData

enum ForbiddenPhraseDefaults {
    /// Стартовые строки из таблицы пользователя (см. spec 2026-07-02).
    static let all: [(phrase: String, problem: String, replacement: String)] = [
        ("кровянистое отделяемое",
         "плохо звучит",
         "кровянистые выделения"),
        ("сразу после операции пациент находится под наблюдением",
         "недостаточно связи: «под наблюдением» — непонятно, под наблюдением кого",
         "сразу после операции пациент находится под наблюдением врачей"),
        ("в период восстановления обычно рекомендуют не сморкаться с усилием",
         "звучит жаргонно",
         "интенсивно прочищать нос"),
        ("хирург работает через носовые ходы",
         "плохо звучит",
         "хирург проводит операцию через носовые ходы"),
        ("обследования показывают нарушение оттока",
         "недостаточно связи",
         "обследования показывают нарушение оттока слизи")
    ]
}

enum ForbiddenPhraseSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ForbiddenPhrase>())) ?? []
        guard existing.isEmpty else { return }
        for (index, item) in ForbiddenPhraseDefaults.all.enumerated() {
            context.insert(ForbiddenPhrase(
                phrase: item.phrase,
                problem: item.problem,
                replacement: item.replacement,
                order: index
            ))
        }
    }
}

enum ForbiddenPhraseRenderer {
    static func render(_ phrases: [ForbiddenPhrase]) -> String {
        let sorted = phrases.sorted { $0.order < $1.order }
        guard !sorted.isEmpty else { return "(список пуст)" }
        return sorted.map { phrase in
            "- «\(phrase.phrase)» — проблема: \(phrase.problem); замена: «\(phrase.replacement)»"
        }.joined(separator: "\n")
    }
}
