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
    @State private var selection: TemplateSelection?
    @State private var category: TemplateCategory = .stagePrompts
    @State private var search = ""

    private var sortedTemplates: [StageTemplate] {
        templates.sorted { lhs, rhs in
            order(lhs.stageRaw) < order(rhs.stageRaw)
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
        PipelineStage.allCases.firstIndex { $0.rawValue == raw } ?? Int.max
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

    private var selectedTemplate: StageTemplate? {
        guard case .stage(let id) = selection else { return nil }
        return templates.first { $0.uuid == id }
    }

    private var selectedRole: AIRole? {
        guard case .role(let id) = selection else { return nil }
        return roles.first { $0.uuid == id }
    }

    private var selectedBlock: ContextBlock? {
        guard case .block(let id) = selection else { return nil }
        return blocks.first { $0.uuid == id }
    }

    private var selectedImagePrompt: ImagePromptTemplate? {
        guard case .imagePrompt(let id) = selection else { return nil }
        return imagePrompts.first { $0.uuid == id }
    }

    private var selectedImagePreset: ImageStylePreset? {
        guard case .imagePreset(let id) = selection else { return nil }
        return imagePresets.first { $0.uuid == id }
    }

    private var selectedEditorDictionary: EditorDictionary? {
        guard case .editorDictionary(let id) = selection else { return nil }
        return editorDictionaries.first { $0.uuid == id }
    }

    private var selectedForbiddenPhrase: ForbiddenPhrase? {
        guard case .forbiddenPhrase(let id) = selection else { return nil }
        return forbiddenPhrases.first { $0.uuid == id }
    }

    private var selectedSkill: SkillPreset? {
        guard case .skill(let id) = selection else { return nil }
        return skills.first { $0.uuid == id }
    }

    private var selectedProductBlock: ProductBlock? {
        guard case .productBlock(let id) = selection else { return nil }
        return productBlocks.first { $0.uuid == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider()
            detail
        }
        .navigationTitle("Шаблоны")
        .toolbar { addToolbar }
        .onAppear(perform: ensureSelection)
        .onChange(of: entityCount) { _, _ in ensureSelection() }
    }

    /// Total number of template entities across all categories. Used to re-run
    /// `ensureSelection` when data loads or items are added/removed. A single
    /// lightweight key keeps the `body` type-checker fast (nine chained
    /// `.onChange(of: … .map(\.uuid))` modifiers time out the compiler).
    private var entityCount: Int {
        templates.count + roles.count + blocks.count + imagePrompts.count
            + imagePresets.count + editorDictionaries.count
            + forbiddenPhrases.count + skills.count + productBlocks.count
    }

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Пресет изображения") {
                    let preset = ImageStylePreset(name: "Новый пресет", styleText: "")
                    context.insert(preset); selection = .imagePreset(preset.uuid); category = .images
                }
                Button("Скилл") {
                    let next = (skills.map(\.order).max() ?? -1) + 1
                    let preset = SkillPreset(name: "Новый скилл", prompt: "", roleKey: "editor", order: next)
                    context.insert(preset); selection = .skill(preset.uuid); category = .skills
                }
                Button("Продуктовый блок") {
                    let next = (productBlocks.map(\.order).max() ?? -1) + 1
                    let block = ProductBlock(name: "Новый блок", prompt: "", order: next)
                    context.insert(block); selection = .productBlock(block.uuid)
                }
                Button("Запрещённую формулировку") {
                    let next = (forbiddenPhrases.map(\.order).max() ?? -1) + 1
                    let phrase = ForbiddenPhrase(phrase: "Новая формулировка", problem: "", replacement: "", order: next)
                    context.insert(phrase); selection = .forbiddenPhrase(phrase.uuid); category = .forbidden
                }
            } label: {
                Label("Добавить", systemImage: "plus")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Категория", selection: $category) {
                ForEach(TemplateCategory.allCases) { cat in
                    Text(cat.title).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(8)

            TextField("Поиск", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8).padding(.bottom, 8)

            List(selection: $selection) {
                if search.isEmpty {
                    categoryRows
                } else {
                    searchRows
                }
            }
        }
    }

    @ViewBuilder
    private var categoryRows: some View {
        switch category {
        case .stagePrompts:
            ForEach(sortedTemplates) { t in
                HStack {
                    Text(t.stage?.title ?? t.stageRaw)
                    Spacer()
                    MetaChip(text: TemplateChipText.chip(model: t.modelName,
                                                         maxTokens: t.maxTokens,
                                                         reasoning: t.reasoningEffort))
                }
                .tag(TemplateSelection.stage(t.uuid))
            }
        case .roles:
            ForEach(sortedRoles) { role in
                Text(role.name).tag(TemplateSelection.role(role.uuid))
            }
        case .editorial:
            ForEach(sortedBlocks) { block in
                Text(block.title).tag(TemplateSelection.block(block.uuid))
            }
            ForEach(editorDictionaries) { dict in
                Text("Словарь правок").tag(TemplateSelection.editorDictionary(dict.uuid))
            }
        case .images:
            ForEach(sortedImagePrompts) { template in
                Text("Промт: \(template.kind?.title ?? template.kindRaw)")
                    .tag(TemplateSelection.imagePrompt(template.uuid))
            }
            ForEach(sortedImagePresets) { preset in
                Text("Пресет: \(preset.name)").tag(TemplateSelection.imagePreset(preset.uuid))
            }
        case .skills:
            ForEach(sortedSkills) { skill in
                Text(skill.name).tag(TemplateSelection.skill(skill.uuid))
            }
        case .forbidden:
            ForEach(sortedForbiddenPhrases) { phrase in
                Text(phrase.phrase).lineLimit(1).tag(TemplateSelection.forbiddenPhrase(phrase.uuid))
            }
        }
    }

    @ViewBuilder
    private var searchRows: some View {
        let q = search.lowercased()
        ForEach(sortedTemplates.filter { ($0.stage?.title ?? $0.stageRaw).lowercased().contains(q) }) { t in
            Text(t.stage?.title ?? t.stageRaw).tag(TemplateSelection.stage(t.uuid))
        }
        ForEach(sortedRoles.filter { $0.name.lowercased().contains(q) }) { role in
            Text(role.name).tag(TemplateSelection.role(role.uuid))
        }
        ForEach(sortedBlocks.filter { $0.title.lowercased().contains(q) }) { block in
            Text(block.title).tag(TemplateSelection.block(block.uuid))
        }
        ForEach(sortedSkills.filter { $0.name.lowercased().contains(q) }) { skill in
            Text(skill.name).tag(TemplateSelection.skill(skill.uuid))
        }
        ForEach(sortedProductBlocks.filter { $0.name.lowercased().contains(q) }) { block in
            Text(block.name).tag(TemplateSelection.productBlock(block.uuid))
        }
        ForEach(sortedForbiddenPhrases.filter { $0.phrase.lowercased().contains(q) }) { phrase in
            Text(phrase.phrase).lineLimit(1).tag(TemplateSelection.forbiddenPhrase(phrase.uuid))
        }
        ForEach(editorDictionaries.filter { _ in "словарь правок".contains(q) }) { dict in
            Text("Словарь правок").tag(TemplateSelection.editorDictionary(dict.uuid))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let t = selectedTemplate {
            TemplateEditorView(template: t).id(t.uuid)
        } else if let role = selectedRole {
            RoleEditorView(role: role, blocks: sortedBlocks).id(role.uuid)
        } else if let block = selectedBlock {
            ContextBlockEditorView(block: block, roles: sortedRoles).id(block.uuid)
        } else if let prompt = selectedImagePrompt {
            ImagePromptEditorView(template: prompt).id(prompt.uuid)
        } else if let preset = selectedImagePreset {
            ImageStylePresetEditorView(preset: preset) { selection = nil }.id(preset.uuid)
        } else if let dict = selectedEditorDictionary {
            EditorDictionaryEditorView(dictionary: dict).id(dict.uuid)
        } else if let phrase = selectedForbiddenPhrase {
            ForbiddenPhraseEditorView(phrase: phrase) { selection = nil }.id(phrase.uuid)
        } else if let skill = selectedSkill {
            SkillEditorView(skill: skill) { selection = nil }.id(skill.uuid)
        } else if let block = selectedProductBlock {
            ProductBlockEditorView(block: block) { selection = nil }.id(block.uuid)
        } else {
            ContentUnavailableView("Выберите шаблон", systemImage: "doc.text")
        }
    }

    private func ensureSelection() {
        if selection != nil { return }
        if let first = sortedTemplates.first {
            selection = .stage(first.uuid)
        } else if let first = sortedRoles.first {
            selection = .role(first.uuid)
        } else if let first = sortedBlocks.first {
            selection = .block(first.uuid)
        } else if let first = sortedImagePrompts.first {
            selection = .imagePrompt(first.uuid)
        } else if let first = sortedImagePresets.first {
            selection = .imagePreset(first.uuid)
        } else if let first = editorDictionaries.first {
            selection = .editorDictionary(first.uuid)
        } else if let first = sortedForbiddenPhrases.first {
            selection = .forbiddenPhrase(first.uuid)
        } else if let first = sortedSkills.first {
            selection = .skill(first.uuid)
        } else if let first = sortedProductBlocks.first {
            selection = .productBlock(first.uuid)
        }
    }
}
