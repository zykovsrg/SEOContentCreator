import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ProductBlockSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ProductBlock.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsDefaultsWhenEmpty() throws {
        let context = try makeContext()
        ProductBlockSeeder.seedIfNeeded(in: context)
        let blocks = try context.fetch(FetchDescriptor<ProductBlock>())
        #expect(blocks.count == ProductBlockDefaults.all.count)
    }

    @Test func doesNotDuplicateOnSecondRun() throws {
        let context = try makeContext()
        ProductBlockSeeder.seedIfNeeded(in: context)
        ProductBlockSeeder.seedIfNeeded(in: context)
        let blocks = try context.fetch(FetchDescriptor<ProductBlock>())
        #expect(blocks.count == ProductBlockDefaults.all.count)
    }
}
