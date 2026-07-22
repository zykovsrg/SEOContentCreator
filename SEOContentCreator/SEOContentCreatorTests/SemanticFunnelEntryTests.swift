import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct SemanticFunnelEntryTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Topic.self, SemanticFunnelEntry.self, configurations: config)
        return ModelContext(container)
    }

    @Test func storesLayerAndReason() throws {
        let context = try makeContext()
        let topic = Topic(title: "Рак груди", articleType: .disease)
        context.insert(topic)

        let entry = SemanticFunnelEntry(
            text: "рак груди реферат",
            frequency: 900,
            layer: .droppedByRules,
            reason: "минус-слово «реферат»",
            runID: UUID()
        )
        entry.topic = topic
        context.insert(entry)

        let stored = try context.fetch(FetchDescriptor<SemanticFunnelEntry>())
        #expect(stored.count == 1)
        #expect(stored[0].layer == .droppedByRules)
        #expect(stored[0].reason == "минус-слово «реферат»")
    }

    @Test func defaultsToRawLayerOnUnknownValue() throws {
        let context = try makeContext()
        let entry = SemanticFunnelEntry(text: "запрос", frequency: nil, layer: .raw, reason: "", runID: UUID())
        context.insert(entry)

        entry.layerRaw = "мусор из будущей версии"

        #expect(entry.layer == .raw)
    }

    @Test func groupsEntriesByRun() throws {
        let context = try makeContext()
        let firstRun = UUID()
        let secondRun = UUID()
        for runID in [firstRun, firstRun, secondRun] {
            context.insert(SemanticFunnelEntry(text: "q", frequency: 10, layer: .survived, reason: "", runID: runID))
        }

        let stored = try context.fetch(FetchDescriptor<SemanticFunnelEntry>())

        #expect(stored.filter { $0.runID == firstRun }.count == 2)
        #expect(stored.filter { $0.runID == secondRun }.count == 1)
    }
}
