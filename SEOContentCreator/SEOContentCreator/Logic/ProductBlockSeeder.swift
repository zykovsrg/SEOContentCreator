import Foundation
import SwiftData

enum ProductBlockSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ProductBlock>())) ?? []
        guard existing.isEmpty else { return }
        for block in ProductBlockDefaults.makeAll() {
            context.insert(block)
        }
    }
}
