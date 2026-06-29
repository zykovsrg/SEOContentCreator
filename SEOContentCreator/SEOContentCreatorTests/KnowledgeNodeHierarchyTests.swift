import Testing
import SwiftData
@testable import SEOContentCreator

@MainActor
struct KnowledgeNodeHierarchyTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KnowledgeNode.self, configurations: config)
        return ModelContext(container)
    }

    @Test func addChildUpdatesParentChildrenAndChildParent() {
        let parent = KnowledgeNode(title: "Раздел", type: .folder)

        let child = parent.addChild(title: "Новый узел", type: .fact)

        #expect(child.parent === parent)
        #expect(parent.children.count == 1)
        #expect(parent.children.first === child)
        #expect(parent.childrenOrNil?.first === child)
    }

    @Test func addChildPersistsAsSingleVisibleChild() throws {
        let context = try makeContext()
        let parent = KnowledgeNode(title: "Раздел", type: .folder)
        context.insert(parent)

        let child = parent.addChild(title: "Новый узел", type: .fact)
        context.insert(child)
        try context.save()

        #expect(child.parent === parent)
        #expect(parent.children.count == 1)
        #expect(parent.childrenOrNil?.count == 1)
        #expect(parent.children.first?.title == "Новый узел")
    }
}
