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

    @Test func seedsAssignDefaultKeys() throws {
        let context = try makeContext()
        ProductBlockSeeder.seedIfNeeded(in: context)
        let blocks = try context.fetch(FetchDescriptor<ProductBlock>())
        let keys = Set(blocks.compactMap { $0.defaultKey })
        #expect(keys == Set(ProductBlockDefaults.all.map { $0.key }))
    }

    @Test func backfillAssignsKeyToLegacyBlockByName() throws {
        let context = try makeContext()
        // Simulate an install seeded before defaultKey existed.
        let def = ProductBlockDefaults.all[0]
        let legacy = ProductBlock(name: def.name, prompt: def.prompt, order: 0)
        legacy.defaultKey = nil
        context.insert(legacy)

        ProductBlockSeeder.seedIfNeeded(in: context)

        #expect(legacy.defaultKey == def.key)
    }

    @Test func resetMatchesByKeyAfterRename() throws {
        let context = try makeContext()
        ProductBlockSeeder.seedIfNeeded(in: context)
        let blocks = try context.fetch(FetchDescriptor<ProductBlock>())
        guard let block = blocks.first else { #expect(Bool(false)); return }

        let originalKey = block.defaultKey
        block.name = "Переименовал как угодно"

        // The editor matches the factory default by key, not name.
        let matched = ProductBlockDefaults.all.first { $0.key == block.defaultKey }
        #expect(matched != nil)
        #expect(matched?.key == originalKey)
    }
}
