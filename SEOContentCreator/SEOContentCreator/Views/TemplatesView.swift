import SwiftUI
import SwiftData

private enum TemplateSelection: Hashable {
    case stage(UUID)
    case role(UUID)
    case block(UUID)
    case imagePrompt(UUID)
    case imagePreset(UUID)
    case editorDictionary(UUID)
    case forbiddenPhrase(UUID)
    case skill(UUID)
    case productBlock(UUID)
}

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query private var templates: [StageTemplate]
    @Query private var roles: [AIRole]
    @Query private var blocks: [ContextBlock]
    @Query private var imagePrompts: [ImagePromptTemplate]
    @Query private var imagePresets: [ImageStylePreset]
    @Query private var editorDictionaries: [EditorDictionary]
    @Query private var forbiddenPhrases: [ForbiddenPhrase]
    @Query private var skills: [SkillPreset]
    @Query private var productBlocks: [ProductBlock]
    @State private var category: TemplateCategory = .stagePrompts
    @State private var search = ""
    @State private var path: [TemplateSelection] = []

    private var sortedTemplates: [StageTemplate] {
        templates.sorted { lhs, rhs in
            order(lhs.stageRaw) < order(rhs.stageRaw)
        }.filter { template in
            guard let stage = template.stage else { return true }
            return stage.kind != .analysis
        }
    }

    private var sortedRoles: [AIRole] {
        roles.sorted { lhs, rhs in
            roleOrder(lhs.key) < roleOrder(rhs.key)
        }
    }

    private var sortedBlocks: [ContextBlock] {
        blocks.sorted { lhs, rhs in
            blockOrder(lhs.key) < blockOrder(rhs.key)
        }
    }

    private var sortedImagePrompts: [ImagePromptTemplate] {
        imagePrompts.sorted { lhs, rhs in
            imagePromptOrder(lhs.kindRaw) < imagePromptOrder(rhs.kindRaw)
        }
    }

    private var sortedImagePresets: [ImageStylePreset] {
        imagePresets.sorted { $0.createdAt < $1.createdAt }
    }

    private var sortedSkills: [SkillPreset] {
        skills.sorted { $0.order < $1.order }
    }

    private var sortedForbiddenPhrases: [ForbiddenPhrase] {
        forbiddenPhrases.sorted { $0.order < $1.order }
    }

    private var sortedProductBlocks: [ProductBlock] {
        productBlocks.sorted { $0.order < $1.order }
    }

    private func order(_ raw: String) -> Int {
        if let workflowIndex = StagePipeline.workflow.firstIndex(where: { $0.rawValue == raw }) {
            return workflowIndex
        }
        return PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    private func roleOrder(_ key: String) -> Int {
        RoleDefaults.all.firstIndex { $0.key == key } ?? Int.max
    }

    private func blockOrder(_ key: String) -> Int {
        ContextBlockDefaults.canonicalOrder.firstIndex(of: key) ?? Int.max
    }

    private func imagePromptOrder(_ raw: String) -> Int {
        ImagePromptKind.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                categoryChipsRow
                Divider()
                templateList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .panelCard()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pageBackground)
            .navigationTitle("Шаблоны")
            .navigationDestination(for: TemplateSelection.self) { sel in
                editorView(for: sel)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Шаблоны").font(.title2).bold()
            Spacer()
            TextField("Поиск", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            addMenu
        }
        .padding()
    }

    private var addMenu: some View {
        Menu {
            Button("Пресет изображения") {
                let preset = ImageStylePreset(name: "Новый пресет", styleText: "")
                context.insert(preset); category = .images; path.append(.imagePreset(preset.uuid))
            }
            Button("Скилл") {
                let next = (skills.map(\.order).max() ?? -1) + 1
                let preset = SkillPreset(name: "Новый скилл", prompt: "", roleKey: "editor", order: next)
                context.insert(preset); category = .skills; path.append(.skill(preset.uuid))
            }
            Button("Продуктовый блок") {
                let next = (productBlocks.map(\.order).max() ?? -1) + 1
                let block = ProductBlock(name: "Новый блок", prompt: "", order: next)
                context.insert(block); path.append(.productBlock(block.uuid))
            }
            Button("Запрещённую формулировку") {
                let next = (forbiddenPhrases.map(\.order).max() ?? -1) + 1
                let phrase = ForbiddenPhrase(phrase: "Новая формулировка", problem: "", replacement: "", order: next)
                context.insert(phrase); category = .forbidden; path.append(.forbiddenPhrase(phrase.uuid))
            }
        } label: {
            Label("Добавить", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
    }

    private var categoryChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(TemplateCategory.allCases) { cat in
                categoryChip(cat)
            }
            Spacer()
        }
        .padding(.horizontal).padding(.bottom, 10)
    }

    private var templateList: some View {
        List {
            if search.isEmpty {
                categoryRows
            } else {
                searchRows
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func categoryChip(_ cat: TemplateCategory) -> some View {
        let selected = category == cat
        return Button { category = cat } label: {
            Text(cat.title)
                .font(.callout).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(Color.accentColor)
                                     : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var categoryRows: some View {
        switch category {
        case .stagePrompts:
            ForEach(sortedTemplates) { t in
                NavigationLink(value: TemplateSelection.stage(t.uuid)) {
                    stageRow(t)
                }
            }
        case .roles:
            ForEach(sortedRoles) { role in
                NavigationLink(role.name, value: TemplateSelection.role(role.uuid))
            }
        case .editorial:
            ForEach(sortedBlocks) { block in
                NavigationLink(block.title, value: TemplateSelection.block(block.uuid))
            }
            ForEach(editorDictionaries) { dict in
                NavigationLink("Словарь правок", value: TemplateSelection.editorDictionary(dict.uuid))
            }
        case .images:
            ForEach(sortedImagePrompts) { template in
                NavigationLink("Промт: \(template.kind?.title ?? template.kindRaw)",
                               value: TemplateSelection.imagePrompt(template.uuid))
            }
            ForEach(sortedImagePresets) { preset in
                NavigationLink("Пресет: \(preset.name)", value: TemplateSelection.imagePreset(preset.uuid))
            }
        case .skills:
            ForEach(sortedSkills) { skill in
                NavigationLink(skill.name, value: TemplateSelection.skill(skill.uuid))
            }
        case .forbidden:
            ForEach(sortedForbiddenPhrases) { phrase in
                NavigationLink(value: TemplateSelection.forbiddenPhrase(phrase.uuid)) {
                    Text(phrase.phrase).lineLimit(1)
                }
            }
        }
    }

    /// Full-width stage-prompt row: title + agent name on the left, model chip
    /// on the right (matches the mockup).
    private func stageRow(_ t: StageTemplate) -> some View {
        HStack(spacing: 8) {
            Text(t.stage?.title ?? t.stageRaw).fontWeight(.medium)
            if let agent = t.stage?.agentName {
                Text(agent).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            MetaChip(text: TemplateChipText.chip(model: t.modelName,
                                                 maxTokens: t.maxTokens,
                                                 reasoning: t.reasoningEffort))
        }
    }

    @ViewBuilder
    private var searchRows: some View {
        let q = search.lowercased()
        ForEach(sortedTemplates.filter { ($0.stage?.title ?? $0.stageRaw).lowercased().contains(q) }) { t in
            NavigationLink(value: TemplateSelection.stage(t.uuid)) { stageRow(t) }
        }
        ForEach(sortedRoles.filter { $0.name.lowercased().contains(q) }) { role in
            NavigationLink(role.name, value: TemplateSelection.role(role.uuid))
        }
        ForEach(sortedBlocks.filter { $0.title.lowercased().contains(q) }) { block in
            NavigationLink(block.title, value: TemplateSelection.block(block.uuid))
        }
        ForEach(sortedSkills.filter { $0.name.lowercased().contains(q) }) { skill in
            NavigationLink(skill.name, value: TemplateSelection.skill(skill.uuid))
        }
        ForEach(sortedProductBlocks.filter { $0.name.lowercased().contains(q) }) { block in
            NavigationLink(block.name, value: TemplateSelection.productBlock(block.uuid))
        }
        ForEach(sortedForbiddenPhrases.filter { $0.phrase.lowercased().contains(q) }) { phrase in
            NavigationLink(value: TemplateSelection.forbiddenPhrase(phrase.uuid)) {
                Text(phrase.phrase).lineLimit(1)
            }
        }
        ForEach(editorDictionaries.filter { _ in "словарь правок".contains(q) }) { dict in
            NavigationLink("Словарь правок", value: TemplateSelection.editorDictionary(dict.uuid))
        }
    }

    @ViewBuilder
    private func editorView(for sel: TemplateSelection) -> some View {
        switch sel {
        case .stage(let id):
            if let t = templates.first(where: { $0.uuid == id }) {
                TemplateEditorView(template: t)
            }
        case .role(let id):
            if let role = roles.first(where: { $0.uuid == id }) {
                RoleEditorView(role: role, blocks: sortedBlocks)
            }
        case .block(let id):
            if let block = blocks.first(where: { $0.uuid == id }) {
                ContextBlockEditorView(block: block, roles: sortedRoles)
            }
        case .imagePrompt(let id):
            if let prompt = imagePrompts.first(where: { $0.uuid == id }) {
                ImagePromptEditorView(template: prompt)
            }
        case .imagePreset(let id):
            if let preset = imagePresets.first(where: { $0.uuid == id }) {
                ImageStylePresetEditorView(preset: preset) { popEditor() }
            }
        case .editorDictionary(let id):
            if let dict = editorDictionaries.first(where: { $0.uuid == id }) {
                EditorDictionaryEditorView(dictionary: dict)
            }
        case .forbiddenPhrase(let id):
            if let phrase = forbiddenPhrases.first(where: { $0.uuid == id }) {
                ForbiddenPhraseEditorView(phrase: phrase) { popEditor() }
            }
        case .skill(let id):
            if let skill = skills.first(where: { $0.uuid == id }) {
                SkillEditorView(skill: skill) { popEditor() }
            }
        case .productBlock(let id):
            if let block = productBlocks.first(where: { $0.uuid == id }) {
                ProductBlockEditorView(block: block) { popEditor() }
            }
        }
    }

    private func popEditor() {
        if !path.isEmpty { path.removeLast() }
    }
}
