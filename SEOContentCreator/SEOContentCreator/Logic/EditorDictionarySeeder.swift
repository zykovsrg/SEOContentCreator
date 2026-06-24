import Foundation
import SwiftData

enum EditorDictionarySeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<EditorDictionary>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(EditorDictionaryDefaults.make())
    }
}
