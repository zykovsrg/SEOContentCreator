import SwiftUI
import SwiftData

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KnowledgeNode.title) private var allNodes: [KnowledgeNode]

    @State private var selection: KnowledgeNode?
    @State private var search = ""

    private var roots: [KnowledgeNode] {
        allNodes.filter { $0.parent == nil }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(roots) { root in
                    OutlineGroup(root, children: \.childrenOrNil) { node in
                        Label(node.title, systemImage: icon(for: node.nodeType))
                            .tag(node)
                    }
                }
            }
            .searchable(text: $search, prompt: "Поиск по справочнику")
            .toolbar {
                ToolbarItem {
                    Button { addRoot() } label: { Label("Узел", systemImage: "plus") }
                }
            }
            .navigationTitle("База знаний")
        } detail: {
            if let node = selection {
                NodeDetailView(node: node)
            } else {
                ContentUnavailableView("Выберите узел", systemImage: "books.vertical")
            }
        }
    }

    private func icon(for type: NodeType) -> String {
        switch type {
        case .direction: return "stethoscope"
        case .doctor:    return "person"
        case .advantage: return "star"
        case .fact:      return "checkmark.seal"
        case .source:    return "link"
        case .folder:    return "folder"
        }
    }

    private func addRoot() {
        let node = KnowledgeNode(title: "Новый раздел", type: .folder)
        context.insert(node)
        selection = node
    }
}

private struct NodeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var node: KnowledgeNode

    var body: some View {
        Form {
            TextField("Заголовок", text: $node.title)
            Picker("Тип", selection: Binding(
                get: { node.nodeType },
                set: { node.nodeType = $0 }
            )) {
                ForEach(NodeType.allCases) { Text($0.title).tag($0) }
            }
            TextField("Содержимое", text: $node.content, axis: .vertical).lineLimit(3...8)
            Section("Действия") {
                Button("Добавить подузел") { addChild() }
                Button("Удалить", role: .destructive) { context.delete(node) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(node.title)
    }

    private func addChild() {
        let child = KnowledgeNode(title: "Новый узел", type: .fact, parent: node)
        context.insert(child)
    }
}
