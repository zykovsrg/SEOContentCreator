import SwiftUI
import SwiftData

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KnowledgeNode.title) private var allNodes: [KnowledgeNode]
    @Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]

    @State private var selection: KnowledgeNode?
    @State private var search = ""
    @State private var selectedTypes: Set<NodeType> = []

    private var roots: [KnowledgeNode] {
        allNodes.filter { $0.parent == nil }
    }

    private var isFiltering: Bool {
        !search.isEmpty || !selectedTypes.isEmpty
    }

    private var searchResults: [KnowledgeNode] {
        var filter = KnowledgeTreeFilter()
        filter.searchText = search
        filter.types = selectedTypes
        return filter.apply(to: allNodes)
    }

    var body: some View {
        HStack(spacing: 10) {
            treePanel
                .frame(width: 390)
                .panelCard(cornerRadius: 12)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelCard(cornerRadius: 12)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
        .navigationTitle("База знаний")
    }

    private var treePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("База знаний").font(.title2).bold()
                Text("\(allNodes.count) узлов")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.controlSurface, in: Capsule())
                Spacer()
                addNodeMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            searchField

            typeFilters
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            Color.hairline.opacity(0.65).frame(height: 1)
            List(selection: $selection) {
                if isFiltering {
                    ForEach(searchResults) { node in
                        treeRow(node)
                            .tag(node)
                    }
                } else {
                    ForEach(roots) { root in
                        OutlineGroup(root, children: \.childrenOrNil) { node in
                            treeRow(node)
                                .tag(node)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск по справочнику", text: $search)
                .textFieldStyle(.plain)
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.selectedControlSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.hairline.opacity(0.65), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var typeFilters: some View {
        FlowLayout(spacing: 6) {
            Button {
                selectedTypes.removeAll()
            } label: {
                Text("Все")
                    .font(.callout).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(selectedTypes.isEmpty ? Color.accentColor : Color.controlSurface, in: Capsule())
                    .foregroundStyle(selectedTypes.isEmpty ? .white : .primary)
            }
            .buttonStyle(.plain)

            ForEach([NodeType.advantage, .fact, .doctor, .source], id: \.self) { type in
                Button {
                    if selectedTypes.contains(type) {
                        selectedTypes.remove(type)
                    } else {
                        selectedTypes.insert(type)
                    }
                } label: {
                    Text(type.title)
                        .font(.callout).fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(selectedTypes.contains(type) ? nodeColor(type) : Color.controlSurface, in: Capsule())
                        .foregroundStyle(selectedTypes.contains(type) ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addNodeMenu: some View {
        Menu {
            ForEach(NodeType.allCases) { type in
                Button(type.title) { addRoot(type: type) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Узел")
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.75)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.brandAccent, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func treeRow(_ node: KnowledgeNode) -> some View {
        HStack(spacing: 8) {
            NodeTypeBadge(type: node.nodeType)
            Text(node.title)
                .lineLimit(1)
            Spacer()
            if node.parent == nil, !node.children.isEmpty {
                Text("\(node.children.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.headline)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var detail: some View {
        if let node = selection {
            NodeDetailView(node: node, topics: topics) {
                selection = nil
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Выберите узел", systemImage: "books.vertical")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addRoot(type: NodeType) {
        let node = KnowledgeNode(title: defaultTitle(for: type), type: type)
        context.insert(node)
        selection = node
    }

    private func defaultTitle(for type: NodeType) -> String {
        switch type {
        case .direction: return "Новое направление"
        case .doctor:    return "Новый врач"
        case .advantage: return "Новое преимущество"
        case .fact:      return "Новый факт"
        case .source:    return "Новый источник"
        case .folder:    return "Новый раздел"
        }
    }
}

private struct NodeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var node: KnowledgeNode
    let topics: [Topic]
    var onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var saveError: String?

    private var usageTopics: [Topic] {
        topics.filter { topic in
            topic.direction === node
                || topic.doctor === node
                || topic.attachedNodes.contains(where: { $0 === node })
        }
    }

    private var pathText: String {
        KnowledgeNodePath.path(for: node).map(\.title).joined(separator: " › ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    contentSection
                    usedInSection
                    childrenSection
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.hairline.opacity(0.65).frame(height: 1)
            bottomBar
        }
        .alert("Не удалось сохранить", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .confirmationDialog("Удалить узел базы знаний?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) {
                onDelete()
                context.delete(node)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(usageTopics.isEmpty
                 ? "Узел будет удалён из базы знаний."
                 : "Этот узел используется в \(usageTopics.count) темах. После удаления брифы и промты могут потерять часть контекста.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pathText)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .top, spacing: 12) {
                TextField("Название узла", text: $node.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .textFieldStyle(.plain)
                Spacer()
                if !usageTopics.isEmpty {
                    Label("Используется в \(usageTopics.count) темах", systemImage: "smallcircle.filled.circle")
                        .font(.callout).fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.rowHighlight, in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                typeMenu
            }
        }
    }

    private var typeMenu: some View {
        Menu {
            ForEach(NodeType.allCases) { type in
                Button(type.title) { node.nodeType = type }
            }
        } label: {
            HStack(spacing: 6) {
                NodeTypeBadge(type: node.nodeType)
                Text(node.nodeType.title)
                    .font(.callout).fontWeight(.semibold)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(nodeColor(node.nodeType).opacity(0.16), in: Capsule())
            .foregroundStyle(nodeColor(node.nodeType))
        }
        .buttonStyle(.plain)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Содержимое")
            TextField("Что важно знать об этом узле", text: $node.content, axis: .vertical)
                .lineLimit(4...10)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(18)
                .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.hairline.opacity(0.55), lineWidth: 1)
                )
        }
    }

    private var usedInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Где используется")
            if usageTopics.isEmpty {
                Text("Пока не привязан к темам")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.selectedControlSurface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline.opacity(0.55)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(usageTopics.enumerated()), id: \.element.id) { index, topic in
                        HStack {
                            Text(topic.title).lineLimit(1)
                            Spacer()
                            Text("\(topic.articleType.title) · \(TopicStatus.compute(for: topic).label)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        if index < usageTopics.count - 1 {
                            Color.hairline.opacity(0.45).frame(height: 1)
                        }
                    }
                }
                .background(Color.selectedControlSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline.opacity(0.55)))
            }
        }
    }

    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Подузлы")
            VStack(spacing: 0) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    HStack {
                        NodeTypeBadge(type: child.nodeType)
                        Text(child.title).lineLimit(1)
                        Spacer()
                        Text(child.nodeType.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    if index < node.children.count - 1 {
                        Color.hairline.opacity(0.45).frame(height: 1)
                    }
                }
                Button {
                    addChild()
                } label: {
                    Label("Добавить подузел", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.headline)
                .padding(.horizontal, 18).padding(.vertical, 13)
            }
            .background(Color.selectedControlSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline.opacity(0.55)))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Удалить узел")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            Spacer()
            Button("Отменить") {
                context.rollback()
            }
            .font(.headline)
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("Сохранить") {
                save()
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func addChild() {
        let child = node.addChild(title: "Новый узел", type: .fact)
        context.insert(child)
    }
}

private struct NodeTypeBadge: View {
    let type: NodeType

    var body: some View {
        Text(shortTitle)
            .font(.caption2)
            .fontWeight(.bold)
            .frame(width: 20, height: 20)
            .background(nodeColor(type), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white)
    }

    private var shortTitle: String {
        switch type {
        case .direction: return "Н"
        case .doctor:    return "В"
        case .advantage: return "П"
        case .fact:      return "Ф"
        case .source:    return "И"
        case .folder:    return "Р"
        }
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}

private func nodeColor(_ type: NodeType) -> Color {
    switch type {
    case .direction: return Color.accentColor
    case .doctor:    return .purple
    case .advantage: return .orange
    case .fact:      return .green
    case .source:    return .secondary
    case .folder:    return .blue
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
