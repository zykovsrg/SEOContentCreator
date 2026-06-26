import Foundation
import SwiftData

enum ProductBlockSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ProductBlock>())) ?? []
        if existing.isEmpty {
            for block in ProductBlockDefaults.makeAll() {
                context.insert(block)
            }
            return
        }
        backfillDefaultKeys(existing)
    }

    /// One-time migration for installs seeded before `defaultKey` existed:
    /// match each keyless block to its factory default by name and assign the key.
    /// After this, renaming the block no longer breaks "reset to default".
    @MainActor
    static func backfillDefaultKeys(_ blocks: [ProductBlock]) {
        for block in blocks where block.defaultKey == nil {
            if let def = ProductBlockDefaults.all.first(where: { $0.name == block.name }) {
                block.defaultKey = def.key
            }
        }
    }
}
