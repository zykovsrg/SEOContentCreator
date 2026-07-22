import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticReferenceSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SemanticStopWord.self, SemanticQueryMask.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsStopWordsWhenEmpty() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<SemanticStopWord>())
        #expect(words.count == SemanticStopWordDefaults.all.count)
        #expect(words.allSatisfy { $0.isEnabled })
    }

    @Test func seedsMasksWhenEmpty() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let masks = try context.fetch(FetchDescriptor<SemanticQueryMask>())
        #expect(masks.count == SemanticQueryMaskDefaults.all.count)
    }

    @Test func doesNotDuplicateOnSecondRun() throws {
        let context = try makeContext()
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        SemanticReferenceSeeder.seedIfNeeded(in: context)
        let words = try context.fetch(FetchDescriptor<SemanticStopWord>())
        let masks = try context.fetch(FetchDescriptor<SemanticQueryMask>())
        #expect(words.count == SemanticStopWordDefaults.all.count)
        #expect(masks.count == SemanticQueryMaskDefaults.all.count)
    }

    @Test func defaultsCoverAcademicQueries() {
        #expect(SemanticStopWordDefaults.all.contains("реферат"))
        #expect(SemanticStopWordDefaults.all.contains("патогенез"))
        #expect(SemanticQueryMaskDefaults.all.contains("как"))
    }
}
