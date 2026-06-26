# Продуктовые блоки из Базы знаний — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить хардкод из 4 продуктовых блоков редактируемыми шаблонами (раздел «Шаблоны»), где каждый блок — название + промт с переменными из Базы знаний; выбранные блоки встраиваются в текст за один запуск через `StageExecutor`.

**Architecture:** Новая аддитивная SwiftData-модель `ProductBlock` (без миграции существующих сущностей). `ProductBlocksSheet` строит список из `@Query`. `PromptBuilder` подставляет KB-переменные в промты выбранных блоков и вшивает их в стадию «Продуктовые блоки» через плейсхолдер `{{продуктовые_блоки}}` с fallback-дописыванием для старых шаблонов. CRUD-секция в `TemplatesView` по образцу секции «Скиллы».

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`, `@Test`, `#expect`). Тест-таргет `SEOContentCreatorTests`.

**Проверка сборки/тестов (важно):** `xcodebuild build-for-testing` для компиляции из CLI. CLI `xcodebuild test` ЗАВИСАЕТ — запуск тестов только в Xcode через **Cmd+U**.

**Политика коммитов:** Проектный `CLAUDE.md` — коммитить только по просьбе пользователя. Шаги «Commit» ниже оставлены по методологии TDD, но выполнять их следует, спросив пользователя; перед первым коммитом завести ветку (сейчас `main`).

---

## File Structure

- Create: `SEOContentCreator/SEOContentCreator/Models/ProductBlock.swift` — SwiftData-модель блока.
- Create: `SEOContentCreator/SEOContentCreator/Logic/ProductBlockDefaults.swift` — дефолтные блоки + фабрики.
- Create: `SEOContentCreator/SEOContentCreator/Logic/ProductBlockSeeder.swift` — разовое сидирование.
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` — регистрация модели в схеме.
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift` — вызов сидера.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift` — вшивание промтов блоков с подстановкой KB-переменных.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift` — плейсхолдер `{{продуктовые_блоки}}` в дефолте стадии.
- Modify: `SEOContentCreator/SEOContentCreator/Views/ProductBlocksSheet.swift` — список из `@Query`, отдаёт промты.
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` — секция «Продуктовые блоки» + `ProductBlockEditorView`.
- Test: `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift` — расширить.
- Test: `SEOContentCreator/SEOContentCreatorTests/ProductBlockSeederTests.swift` — создать.

---

## Task 1: Модель `ProductBlock` + регистрация в схеме

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/ProductBlock.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift:15`

- [ ] **Step 1: Создать модель**

`SEOContentCreator/SEOContentCreator/Models/ProductBlock.swift`:

```swift
import Foundation
import SwiftData

@Model
final class ProductBlock {
    var uuid: UUID
    var name: String
    var prompt: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(name: String, prompt: String, order: Int) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 2: Зарегистрировать модель в схеме**

В `SEOContentCreatorApp.swift` строка 15 — добавить `ProductBlock.self` в список Schema. Текущая строка:

```swift
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self
```

Заменить на:

```swift
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self,
            ProductBlock.self
```

- [ ] **Step 3: Проверить компиляцию**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj`
(адаптировать имя scheme/проекта при необходимости)
Expected: BUILD SUCCEEDED. (Новый файл должен автоматически попасть в таргет; если проект использует ручные membership — добавить файл в таргет в Xcode.)

- [ ] **Step 4: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Models/ProductBlock.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift
git commit -m "feat(product-blocks): add ProductBlock SwiftData model"
```

---

## Task 2: `PromptBuilder` — вшивание промтов блоков с подстановкой KB-переменных

Логика ядра, делаем по TDD. `selectedBlocks: [String]` теперь содержит **промты** выбранных блоков (а не имена). К каждому промту применяются те же подстановки, что и к шаблону стадии. Результат вставляется в `{{продуктовые_блоки}}`; если плейсхолдера нет — дописывается в конец.

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`

- [ ] **Step 1: Написать падающие тесты**

Добавить в `PromptBuilderTests.swift` (внутри `struct PromptBuilderTests`):

```swift
    @Test func selectedBlockPromptsInjectedViaPlaceholder() {
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}\nБлоки:\n{{продуктовые_блоки}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: "тело",
            selectedBlocks: ["Промт А", "Промт Б"]
        )
        #expect(result.user.contains("Промт А"))
        #expect(result.user.contains("Промт Б"))
        #expect(!result.user.contains("{{продуктовые_блоки}}"))
    }

    @Test func knowledgeVariablesInsideBlockPromptSubstituted() {
        let doctor = KnowledgeNode(title: "Врач", type: .doctor, content: "Иванов И.И., онколог")
        let topic = Topic(title: "T", articleType: .info)
        topic.doctor = doctor
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "{{продуктовые_блоки}}")
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: nil,
            selectedBlocks: ["Данные врача: {{врач_данные}}"]
        )
        #expect(result.user.contains("Данные врача: Иванов И.И., онколог"))
    }

    @Test func blocksAppendedWhenNoPlaceholder() {
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "Текст: {{текущий_текст}}")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(
            template: t, topic: topic, currentText: "тело",
            selectedBlocks: ["Блок CTA"]
        )
        #expect(result.user.contains("Блок CTA"))
        #expect(result.user.contains("Текст: тело"))
    }

    @Test func emptyPlaceholderRemovedWhenNoBlocks() {
        let t = StageTemplate(stage: .productBlocks, systemPrompt: "x",
                              userPromptTemplate: "A {{продуктовые_блоки}} B")
        let topic = Topic(title: "T", articleType: .info)
        let result = PromptBuilder().build(template: t, topic: topic, currentText: nil)
        #expect(!result.user.contains("{{продуктовые_блоки}}"))
    }
```

Проверить, что у `NodeType` есть кейс `.doctor` (используется в тесте). Если имя другого кейса — поправить тест под реальный enum (см. `Models/KnowledgeNode.swift` / `NodeType`). Подстановка `{{врач_данные}}` берётся из `topic.doctor?.content`.

- [ ] **Step 2: Запустить тесты — убедиться, что падают**

Cmd+U в Xcode (CLI `xcodebuild test` зависает).
Expected: 4 новых теста FAIL (плейсхолдер не обрабатывается / блоки идут как имена через старую строку «Включить продуктовые блоки:»).

- [ ] **Step 3: Реализовать**

В `PromptBuilder.swift` заменить тело после построения словаря `substitutions` (строки ~37–43, блок `for (key, value)...` и `if !selectedBlocks.isEmpty {...}`) на:

```swift
        func substitute(_ text: String) -> String {
            var result = text
            for (key, value) in substitutions {
                result = result.replacingOccurrences(of: key, with: value)
            }
            return result
        }

        user = substitute(user)

        let renderedBlocks = selectedBlocks
            .map { substitute($0) }
            .joined(separator: "\n\n")

        if renderedBlocks.isEmpty {
            user = user.replacingOccurrences(of: "{{продуктовые_блоки}}", with: "")
        } else if user.contains("{{продуктовые_блоки}}") {
            user = user.replacingOccurrences(of: "{{продуктовые_блоки}}", with: renderedBlocks)
        } else {
            user += "\n\nПродуктовые блоки для встраивания:\n" + renderedBlocks
        }
```

Удалить прежний цикл `for (key, value) in substitutions { user = ... }` и прежний блок `if !selectedBlocks.isEmpty { user += "\n\nВключить продуктовые блоки: " ... }` — их заменяет код выше.

- [ ] **Step 4: Запустить тесты — убедиться, что проходят**

Cmd+U в Xcode.
Expected: все тесты `PromptBuilderTests` PASS (включая существующие — `substitutesBriefVariables`, `unknownPlaceholdersLeftAsIs`, `currentTextAndSemanticsSubstituted`).

- [ ] **Step 5: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift
git commit -m "feat(product-blocks): inject block prompts with KB variables into stage prompt"
```

---

## Task 3: Плейсхолдер `{{продуктовые_блоки}}` в дефолте стадии

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift` (кейс `.productBlocks`, строки ~53–67)

- [ ] **Step 1: Обновить дефолтный промт стадии**

Заменить `userPromptTemplate` в кейсе `.productBlocks` на:

```swift
                userPromptTemplate: """
                Встрой выбранные продуктовые блоки в текст, не ломая его структуру.

                Текущий текст:
                {{текущий_текст}}

                Продуктовые блоки для встраивания:
                {{продуктовые_блоки}}

                Верни полный обновлённый текст статьи.
                """
```

(Старые сохранённые шаблоны в SwiftData не изменятся — для них работает fallback-дописывание из Task 2. Новый плейсхолдер виден на свежих установках и после кнопки «Сбросить к стандартному».)

- [ ] **Step 2: Проверить компиляцию**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift
git commit -m "feat(product-blocks): add product-blocks placeholder to stage default prompt"
```

---

## Task 4: Дефолты + сидер + тест сидера

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/ProductBlockDefaults.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ProductBlockSeeder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift:24` (рядом с `SkillPresetSeeder.seedIfNeeded`)
- Test: `SEOContentCreator/SEOContentCreatorTests/ProductBlockSeederTests.swift`

- [ ] **Step 1: Создать дефолты**

`SEOContentCreator/SEOContentCreator/Logic/ProductBlockDefaults.swift`:

```swift
import Foundation

struct ProductBlockDefault {
    let name: String
    let prompt: String
}

enum ProductBlockDefaults {
    static let all: [ProductBlockDefault] = [
        ProductBlockDefault(
            name: "CTA «Записаться»",
            prompt: "Добавь короткий призыв записаться на приём. Без давления и преувеличений, по делу."
        ),
        ProductBlockDefault(
            name: "Почему мы",
            prompt: "Сформируй блок «Почему мы» на основе преимуществ клиники: {{преимущества}}. Только факты из данных, ничего не выдумывай."
        ),
        ProductBlockDefault(
            name: "Блок врача",
            prompt: "Добавь блок о враче на основе данных: {{врач_данные}}. Если данных нет — пропусти блок."
        ),
        ProductBlockDefault(
            name: "Преимущества клиники",
            prompt: "Перечисли преимущества клиники: {{преимущества}}. Кратко, по пунктам, без рекламных штампов."
        )
    ]

    static func make(_ def: ProductBlockDefault, order: Int) -> ProductBlock {
        ProductBlock(name: def.name, prompt: def.prompt, order: order)
    }

    static func makeAll() -> [ProductBlock] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
```

- [ ] **Step 2: Создать сидер**

`SEOContentCreator/SEOContentCreator/Logic/ProductBlockSeeder.swift`:

```swift
import Foundation
import SwiftData

enum ProductBlockSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ProductBlock>())) ?? []
        guard existing.isEmpty else { return }
        for block in ProductBlockDefaults.makeAll() {
            context.insert(block)
        }
    }
}
```

- [ ] **Step 3: Написать падающий тест сидера**

`SEOContentCreator/SEOContentCreatorTests/ProductBlockSeederTests.swift` (по образцу `StageTemplateSeederTests.swift` — свериться с реальным файлом на способ создания in-memory `ModelContext`):

```swift
import Testing
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
```

- [ ] **Step 4: Запустить тест — убедиться, что падает/не компилируется**

Cmd+U.
Expected: FAIL/не компилируется до создания файлов из шагов 1–2 (если subagent пишет тест первым — сначала будет ошибка отсутствия типа).

- [ ] **Step 5: Подключить сидер в RootView**

В `RootView.swift` после строки 24 (`SkillPresetSeeder.seedIfNeeded(in: context)`) добавить:

```swift
            ProductBlockSeeder.seedIfNeeded(in: context)
```

- [ ] **Step 6: Запустить тест — убедиться, что проходит**

Cmd+U.
Expected: оба теста `ProductBlockSeederTests` PASS.

- [ ] **Step 7: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ProductBlockDefaults.swift SEOContentCreator/SEOContentCreator/Logic/ProductBlockSeeder.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift SEOContentCreator/SEOContentCreatorTests/ProductBlockSeederTests.swift
git commit -m "feat(product-blocks): seed default product blocks on launch"
```

---

## Task 5: `ProductBlocksSheet` — список из `@Query`, отдаёт промты

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/ProductBlocksSheet.swift`

`onGenerate: ([String]) -> Void` остаётся, но теперь отдаёт **промты** выбранных блоков. `TopicWorkspaceView` не меняется (`runStage(.productBlocks, blocks: $0)`).

- [ ] **Step 1: Переписать sheet на `@Query`**

Заменить содержимое `ProductBlocksSheet.swift` на:

```swift
import SwiftUI
import SwiftData

struct ProductBlocksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProductBlock.order) private var blocks: [ProductBlock]
    @Bindable var topic: Topic
    /// Передаёт промты выбранных блоков (а не имена).
    var onGenerate: ([String]) -> Void

    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите продуктовые блоки").font(.headline)
            if blocks.isEmpty {
                ContentUnavailableView(
                    "Нет продуктовых блоков",
                    systemImage: "square.stack.3d.up",
                    description: Text("Добавьте блоки в разделе «Шаблоны».")
                )
            } else {
                List {
                    ForEach(blocks) { block in
                        Toggle(isOn: Binding(
                            get: { selected.contains(block.uuid) },
                            set: { if $0 { selected.insert(block.uuid) } else { selected.remove(block.uuid) } }
                        )) { Text(block.name) }
                    }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сгенерировать") {
                    let prompts = blocks
                        .filter { selected.contains($0.uuid) }
                        .map(\.prompt)
                    onGenerate(prompts)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 360)
    }
}
```

- [ ] **Step 2: Проверить компиляцию**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Views/ProductBlocksSheet.swift
git commit -m "feat(product-blocks): build ProductBlocksSheet from stored blocks"
```

---

## Task 6: Секция «Продуктовые блоки» в `TemplatesView` + редактор

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`

Делаем строго по образцу секции «Скиллы» (`TemplateSelection.skill`, `SkillEditorView`).

- [ ] **Step 1: Добавить кейс в enum выбора**

В `TemplateSelection` (строки 6–14) после `case skill(UUID)` добавить:

```swift
    case productBlock(UUID)
```

- [ ] **Step 2: Добавить `@Query`, сортировку и selected-helper**

После `@Query private var skills: [SkillPreset]` (строка 24) добавить:

```swift
    @Query private var productBlocks: [ProductBlock]
```

После `sortedSkills` (строки 55–57) добавить:

```swift
    private var sortedProductBlocks: [ProductBlock] {
        productBlocks.sorted { $0.order < $1.order }
    }
```

После `selectedSkill` (строки 105–108) добавить:

```swift
    private var selectedProductBlock: ProductBlock? {
        guard case .productBlock(let id) = selection else { return nil }
        return productBlocks.first { $0.uuid == id }
    }
```

- [ ] **Step 3: Добавить секцию в sidebar**

После закрытия `Section("Скиллы") { ... }` (после строки 167) добавить:

```swift
                Section("Продуктовые блоки") {
                    ForEach(sortedProductBlocks) { block in
                        Text(block.name).tag(TemplateSelection.productBlock(block.uuid))
                    }
                    Button {
                        let next = (productBlocks.map(\.order).max() ?? -1) + 1
                        let block = ProductBlock(name: "Новый блок", prompt: "", order: next)
                        context.insert(block)
                        selection = .productBlock(block.uuid)
                    } label: {
                        Label("Добавить блок", systemImage: "plus")
                    }
                }
```

- [ ] **Step 4: Добавить onChange и ветку detail**

После `.onChange(of: skills.map(\.uuid)) { _, _ in ensureSelection() }` (строка 181) добавить:

```swift
        .onChange(of: productBlocks.map(\.uuid)) { _, _ in ensureSelection() }
```

В `detail` после ветки `else if let skill = selectedSkill { ... }` (строки 198–199) добавить:

```swift
        } else if let block = selectedProductBlock {
            ProductBlockEditorView(block: block) { selection = nil }.id(block.uuid)
```

В `ensureSelection()` после ветки `else if let first = sortedSkills.first { selection = .skill(first.uuid) }` (строки 219–220) добавить:

```swift
        } else if let first = sortedProductBlocks.first {
            selection = .productBlock(first.uuid)
```

- [ ] **Step 5: Добавить `ProductBlockEditorView`**

В конец файла `TemplatesView.swift` добавить (по образцу `SkillEditorView`, строки 728–807):

```swift
private struct ProductBlockEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var block: ProductBlock
    var onDelete: () -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var savedNote: String?

    private var defaultForBlock: ProductBlockDefault? {
        ProductBlockDefaults.all.first { $0.name == block.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Продуктовый блок").font(.title2).bold()

                TextField("Название", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Text("Промт (что встроить в текст)").font(.headline)
                Text("Доступные переменные: {{преимущества}}, {{врач_данные}}, {{направление}}, {{тема}}")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $prompt).frame(minHeight: 180).border(.gray.opacity(0.3))

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    if defaultForBlock != nil {
                        Button("Сбросить к стандартному") { resetToDefault() }
                    }
                    Spacer()
                    Button("Удалить блок", role: .destructive) { deleteBlock() }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = block.name
        prompt = block.prompt
    }

    private func save() {
        block.name = name
        block.prompt = prompt
        block.updatedAt = .now
        savedNote = "Сохранено"
    }

    private func resetToDefault() {
        guard let def = defaultForBlock else { return }
        prompt = def.prompt
        save()
        savedNote = "Сброшено к стандартному"
    }

    private func deleteBlock() {
        context.delete(block)
        onDelete()
    }
}
```

- [ ] **Step 6: Проверить компиляцию**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Ручная проверка (Cmd+R)**

1. Открыть «Шаблоны» → секция «Продуктовые блоки»: видно 4 дефолта; добавить/редактировать/удалить/сброс работают.
2. В теме открыть «Продуктовые блоки» (`ProductBlocksSheet`): список из тех же блоков; выбрать 1–2 → «Сгенерировать» → блоки встраиваются в текст.

- [ ] **Step 8: Commit** (по просьбе пользователя)

```bash
git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "feat(product-blocks): add Product Blocks CRUD section in Templates"
```

---

## Финальная проверка

- [ ] `xcodebuild build-for-testing` — зелёный.
- [ ] Cmd+U в Xcode — все тесты зелёные (новые `PromptBuilderTests` + `ProductBlockSeederTests`, прежние не сломаны).
- [ ] Ручная проверка из Task 6 Step 7 пройдена.
- [ ] Предложить `task-finish`.

## Self-Review (выполнено при написании плана)

- **Покрытие спеки:** модель (T1) ✓, сидирование дефолтов (T4) ✓, проводка в генерацию один-запуск с `{{продуктовые_блоки}}` + fallback (T2, T3, T5) ✓, KB-переменные внутри блока (T2) ✓, CRUD-секция (T6) ✓, тесты PromptBuilder + Seeder (T2, T4) ✓.
- **Плейсхолдеры:** нет TODO/TBD; весь код приведён.
- **Согласованность типов:** `ProductBlock(name:prompt:order:)`, `ProductBlockDefaults.all/makeAll()`, `ProductBlockSeeder.seedIfNeeded(in:)`, `TemplateSelection.productBlock`, `ProductBlockEditorView` — имена совпадают во всех задачах. `selectedBlocks: [String]` (промты) — сигнатура `PromptBuilder.build`/`StageExecutor.execute` не меняется по типу.
- **Точка внимания при исполнении:** проверить реальное имя кейса `NodeType.doctor` и способ создания in-memory `ModelContext` в существующем `StageTemplateSeederTests.swift`; при расхождении — подогнать тесты.
