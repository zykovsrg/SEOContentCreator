import SwiftUI
import SwiftData

private enum TemplateSelection: Hashable {
    case stage(UUID)
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
    @State private var category: TemplateCategory = .stages
    @State private var search = ""
    @State private var path: [TemplateSelection] = []
    @State private var hoveredSelection: TemplateSelection?
    @State private var selectedSelection: TemplateSelection?

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
                categoryTabsRow
                if category == .semantics {
                    SemanticReferenceEditorView()
                } else {
                    templateList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .panelCard(cornerRadius: 12)
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
            searchField
            addMenu
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск...", text: $search)
                .textFieldStyle(.plain)
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .frame(minWidth: 190, idealWidth: 300, maxWidth: 300, minHeight: 44)
        .background(Color.selectedControlSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.hairline.opacity(0.65), lineWidth: 1)
        )
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Добавить")
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.75)
            }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Color.brandAccent, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var categoryTabsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TemplateCategory.allCases) { cat in
                    categoryTab(cat)
                }
            }
            .padding(3)
            .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if search.isEmpty {
                    categoryRows
                } else {
                    searchRows
                }
            }
        }
        .background(Color.selectedControlSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.hairline.opacity(0.70), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func categoryTab(_ cat: TemplateCategory) -> some View {
        let selected = category == cat
        return Button { category = cat } label: {
            Text(cat.title)
                .font(.headline)
                .lineLimit(1)
                .frame(minWidth: 116)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(selected ? Color.selectedControlSurface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selected ? Color.hairline.opacity(0.70) : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var categoryRows: some View {
        switch category {
        case .stages:
            ForEach(sortedTemplates) { t in
                rowButton(
                    value: .stage(t.uuid),
                    title: t.stage?.title ?? t.stageRaw,
                    subtitle: t.stage?.agentName,
                    chip: TemplateChipText.chip(model: t.modelName,
                                                maxTokens: t.maxTokens,
                                                reasoning: t.reasoningEffort)
                )
            }
        case .images:
            ForEach(sortedImagePrompts) { template in
                rowButton(
                    value: .imagePrompt(template.uuid),
                    title: template.kind?.title ?? template.kindRaw,
                    subtitle: "Промт изображения"
                )
            }
            ForEach(sortedImagePresets) { preset in
                rowButton(value: .imagePreset(preset.uuid), title: preset.name, subtitle: "Пресет")
            }
        case .skills:
            ForEach(sortedSkills) { skill in
                rowButton(value: .skill(skill.uuid), title: skill.name, subtitle: "Скилл")
            }
        case .forbidden:
            ForEach(sortedForbiddenPhrases) { phrase in
                rowButton(value: .forbiddenPhrase(phrase.uuid), title: phrase.phrase, subtitle: phrase.replacement)
            }
            ForEach(editorDictionaries) { dict in
                rowButton(value: .editorDictionary(dict.uuid), title: "Словарь правок", subtitle: "Редполитика")
            }
        case .semantics:
            EmptyView() // Rendered directly in body via SemanticReferenceEditorView, bypassing the row list.
        }
    }

    private func rowButton(value: TemplateSelection, title: String, subtitle: String? = nil, chip: String? = nil) -> some View {
        Button {
            selectedSelection = value
            path.append(value)
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(minWidth: 0, alignment: .leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                if let chip {
                    MetaChip(text: chip)
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)
            .contentShape(Rectangle())
            .background(rowBackground(for: value))
            .overlay(alignment: .bottom) {
                Color.hairline.opacity(0.55).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredSelection = isHovered ? value : nil
        }
    }

    private func rowBackground(for value: TemplateSelection) -> Color {
        if selectedSelection == value || hoveredSelection == value {
            return Color.rowHighlight
        }
        return Color.clear
    }

    @ViewBuilder
    private var searchRows: some View {
        let q = search.lowercased()
        ForEach(sortedTemplates.filter { ($0.stage?.title ?? $0.stageRaw).lowercased().contains(q) }) { t in
            rowButton(
                value: .stage(t.uuid),
                title: t.stage?.title ?? t.stageRaw,
                subtitle: t.stage?.agentName,
                chip: TemplateChipText.chip(model: t.modelName,
                                            maxTokens: t.maxTokens,
                                            reasoning: t.reasoningEffort)
            )
        }
        ForEach(sortedSkills.filter { $0.name.lowercased().contains(q) }) { skill in
            rowButton(value: .skill(skill.uuid), title: skill.name, subtitle: "Скилл")
        }
        ForEach(sortedProductBlocks.filter { $0.name.lowercased().contains(q) }) { block in
            rowButton(value: .productBlock(block.uuid), title: block.name, subtitle: "Продуктовый блок")
        }
        ForEach(sortedForbiddenPhrases.filter { $0.phrase.lowercased().contains(q) }) { phrase in
            rowButton(value: .forbiddenPhrase(phrase.uuid), title: phrase.phrase, subtitle: phrase.replacement)
        }
        ForEach(editorDictionaries.filter { _ in "словарь правок".contains(q) }) { dict in
            rowButton(value: .editorDictionary(dict.uuid), title: "Словарь правок", subtitle: "Редполитика")
        }
    }

    @ViewBuilder
    private func editorView(for sel: TemplateSelection) -> some View {
        switch sel {
        case .stage(let id):
            if let t = templates.first(where: { $0.uuid == id }) {
                StagePromptEditorView(
                    template: t,
                    role: t.stage.flatMap { stage in sortedRoles.first { $0.key == stage.roleKey } },
                    blocks: sortedBlocks,
                    allRoles: sortedRoles
                )
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
