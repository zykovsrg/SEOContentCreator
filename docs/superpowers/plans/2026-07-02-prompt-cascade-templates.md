# Prompt Cascade Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Встроить ручной каскад промтов пользователя в дефолтные шаблоны приложения и добавить редактируемую таблицу запрещённых формулировок.

**Architecture:** Обновить дефолтные тексты (StageTemplateDefaults ×4, ContextBlockDefaults ×2, RoleDefaults author, новый SkillPreset `shorten`) и доставить их в существующую БД через версионную миграцию v3 в StageTemplateSeeder. Добавить standalone SwiftData-модель `ForbiddenPhrase` (без связей с Topic), сидер с 5 стартовыми строками, рендерер для промта, плейсхолдер `{{запрещённые_формулировки}}` в PromptBuilder (подставляется из StageExecutor) и раздел редактирования в TemplatesView.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, xcodebuild.

Spec: `docs/superpowers/specs/2026-07-02-prompt-cascade-templates-design.md` — точные тексты промтов брать ТОЛЬКО оттуда.

---

## File Map

- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift` — новые userPromptTemplate для structure/draft/factCheck/finalReview.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/RoleDefaults.swift` — mandate роли author + тексты блоков editorialPolicy/sources.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift` — пресет `shorten`.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift` — миграция v3.
- Create: `SEOContentCreator/SEOContentCreator/Models/ForbiddenPhrase.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ForbiddenPhraseSeeder.swift` — defaults + seeder + renderer.
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` — регистрация модели.
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift` — вызов сидера.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift` — параметр forbiddenPhrases.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift` — новый токен.
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift` — fetch + передача (3 места).
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` — секция «Запрещённые формулировки».
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ForbiddenPhraseEditorView.swift`
- Tests: `SEOContentCreator/SEOContentCreatorTests/ForbiddenPhraseTests.swift`, `TemplatesMigrationV3Tests.swift`, дополнение `PromptBuilderTests.swift`.

## Test Command

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'
```

Ожидание: `** TEST SUCCEEDED **`. Все команды xcodebuild запускать из подпапки `SEOContentCreator/` (там лежит .xcodeproj).

---

### Task 0: Feature branch

- [ ] **Step 1: Создать ветку**

```bash
git checkout -b feature/prompt-cascade-templates
```

---

### Task 1: ForbiddenPhrase — модель, сидер, рендерер

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/ForbiddenPhrase.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/ForbiddenPhraseSeeder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ForbiddenPhraseTests.swift`

- [ ] **Step 1: Написать падающие тесты**

Создать `SEOContentCreator/SEOContentCreatorTests/ForbiddenPhraseTests.swift`:

```swift
import Testing
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ForbiddenPhraseTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ForbiddenPhrase.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsFiveDefaultPhrasesOnce() throws {
        let context = try makeContext()

        ForbiddenPhraseSeeder.seedIfNeeded(in: context)
        ForbiddenPhraseSeeder.seedIfNeeded(in: context)

        let phrases = try context.fetch(FetchDescriptor<ForbiddenPhrase>())
        #expect(phrases.count == 5)
        #expect(phrases.contains { $0.phrase == "кровянистое отделяемое" })
    }

    @Test func rendersPhrasesForPrompt() {
        let phrase = ForbiddenPhrase(
            phrase: "кровянистое отделяемое",
            problem: "плохо звучит",
            replacement: "кровянистые выделения",
            order: 0
        )

        let rendered = ForbiddenPhraseRenderer.render([phrase])

        #expect(rendered.contains("«кровянистое отделяемое»"))
        #expect(rendered.contains("плохо звучит"))
        #expect(rendered.contains("«кровянистые выделения»"))
    }

    @Test func rendersEmptyListPlaceholder() {
        #expect(ForbiddenPhraseRenderer.render([]) == "(список пуст)")
    }
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ForbiddenPhraseTests
```

Ожидание: сборка падает — `ForbiddenPhrase` не существует.

- [ ] **Step 3: Создать модель**

Создать `SEOContentCreator/SEOContentCreator/Models/ForbiddenPhrase.swift`:

```swift
import Foundation
import SwiftData

@Model
final class ForbiddenPhrase {
    var uuid: UUID
    /// Предложение или формулировка, которую нельзя использовать.
    var phrase: String
    /// В чём проблема.
    var problem: String
    /// Как можно заменить.
    var replacement: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(phrase: String, problem: String, replacement: String, order: Int) {
        self.uuid = UUID()
        self.phrase = phrase
        self.problem = problem
        self.replacement = replacement
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Создать сидер и рендерер**

Создать `SEOContentCreator/SEOContentCreator/Logic/ForbiddenPhraseSeeder.swift`:

```swift
import Foundation
import SwiftData

enum ForbiddenPhraseDefaults {
    /// Стартовые строки из таблицы пользователя (см. spec 2026-07-02).
    static let all: [(phrase: String, problem: String, replacement: String)] = [
        ("кровянистое отделяемое",
         "плохо звучит",
         "кровянистые выделения"),
        ("сразу после операции пациент находится под наблюдением",
         "недостаточно связи: «под наблюдением» — непонятно, под наблюдением кого",
         "сразу после операции пациент находится под наблюдением врачей"),
        ("в период восстановления обычно рекомендуют не сморкаться с усилием",
         "звучит жаргонно",
         "интенсивно прочищать нос"),
        ("хирург работает через носовые ходы",
         "плохо звучит",
         "хирург проводит операцию через носовые ходы"),
        ("обследования показывают нарушение оттока",
         "недостаточно связи",
         "обследования показывают нарушение оттока слизи")
    ]
}

enum ForbiddenPhraseSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ForbiddenPhrase>())) ?? []
        guard existing.isEmpty else { return }
        for (index, item) in ForbiddenPhraseDefaults.all.enumerated() {
            context.insert(ForbiddenPhrase(
                phrase: item.phrase,
                problem: item.problem,
                replacement: item.replacement,
                order: index
            ))
        }
    }
}

enum ForbiddenPhraseRenderer {
    static func render(_ phrases: [ForbiddenPhrase]) -> String {
        let sorted = phrases.sorted { $0.order < $1.order }
        guard !sorted.isEmpty else { return "(список пуст)" }
        return sorted.map { phrase in
            "- «\(phrase.phrase)» — проблема: \(phrase.problem); замена: «\(phrase.replacement)»"
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Зарегистрировать модель и сидер**

В `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` в список `.modelContainer(for: [...])` добавить `ForbiddenPhrase.self` после `ProductBlock.self`.

В `SEOContentCreator/SEOContentCreator/Views/RootView.swift` после строки `ProductBlockSeeder.seedIfNeeded(in: context)` добавить:

```swift
ForbiddenPhraseSeeder.seedIfNeeded(in: context)
```

- [ ] **Step 6: Прогнать тесты**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/ForbiddenPhraseTests
```

Ожидание: PASS.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/ForbiddenPhrase.swift SEOContentCreator/SEOContentCreator/Logic/ForbiddenPhraseSeeder.swift SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift SEOContentCreator/SEOContentCreator/Views/RootView.swift SEOContentCreator/SEOContentCreatorTests/ForbiddenPhraseTests.swift
git commit -m "Add forbidden phrase model"
```

---

### Task 2: PromptBuilder — плейсхолдер {{запрещённые_формулировки}}

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift`

- [ ] **Step 1: Добавить падающий тест**

В `SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift` добавить (внутрь существующей тестовой структуры):

```swift
@Test func substitutesForbiddenPhrasesPlaceholder() {
    let t = StageTemplate(stage: .finalReview, systemPrompt: "x",
                          userPromptTemplate: "Запрещено:\n{{запрещённые_формулировки}}")
    let topic = Topic(title: "T", articleType: .info)

    let result = PromptBuilder().build(
        template: t, topic: topic, currentText: "текст",
        forbiddenPhrases: "- «плохая фраза» — проблема: звучит плохо; замена: «хорошая фраза»"
    )

    #expect(result.user.contains("«плохая фраза»"))
}

@Test func emptyForbiddenPhrasesFallsBackToStub() {
    let t = StageTemplate(stage: .finalReview, systemPrompt: "x",
                          userPromptTemplate: "Запрещено:\n{{запрещённые_формулировки}}")
    let topic = Topic(title: "T", articleType: .info)

    let result = PromptBuilder().build(template: t, topic: topic, currentText: "текст")

    #expect(result.user.contains("(список пуст)"))
}
```

Примечание: сигнатуру существующих вызовов `build` в этом файле не менять — новый параметр будет со значением по умолчанию.

- [ ] **Step 2: Убедиться, что тесты падают**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests
```

Ожидание: сборка падает — у `build` нет параметра `forbiddenPhrases`.

- [ ] **Step 3: Реализовать**

В `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`:

1. В сигнатуру `build` добавить параметр (после `roleContext: String = ""`):

```swift
forbiddenPhrases: String = ""
```

2. В словарь `substitutions` добавить:

```swift
"{{запрещённые_формулировки}}": forbiddenPhrases.isEmpty ? "(список пуст)" : forbiddenPhrases,
```

В `SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift` в конец массива `all` добавить:

```swift
TemplateVariable(token: "{{запрещённые_формулировки}}", description: "Таблица запрещённых формулировок", source: "Шаблоны → Запрещённые формулировки")
```

- [ ] **Step 4: Прогнать тесты**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/PromptBuilderTests
```

Ожидание: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift SEOContentCreator/SEOContentCreatorTests/PromptBuilderTests.swift
git commit -m "Substitute forbidden phrases placeholder"
```

---

### Task 3: StageExecutor — передача формулировок в промт

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`

- [ ] **Step 1: Добавить хелпер**

В `StageExecutor` рядом с `fetchRole`/`buildRoleContext` добавить:

```swift
private func fetchForbiddenPhrases(in context: ModelContext) -> String {
    let phrases = (try? context.fetch(FetchDescriptor<ForbiddenPhrase>())) ?? []
    return ForbiddenPhraseRenderer.render(phrases)
}
```

- [ ] **Step 2: Передать во все три вызова PromptBuilder**

В `StageExecutor.swift` три вызова `PromptBuilder().build(` (методы `execute`, `executeSandbox`, `executeQuickCheck`, строки ~72/163/232). В каждый добавить аргумент:

```swift
forbiddenPhrases: fetchForbiddenPhrases(in: context)
```

- [ ] **Step 3: Сборка и smoke-тест**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageExecutorTests
```

Ожидание: PASS (существующие тесты executor не сломаны; их in-memory контейнеры не содержат ForbiddenPhrase — fetch вернёт ошибку, `try?` даст пустой список, рендер вернёт заглушку).

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift
git commit -m "Feed forbidden phrases into stage prompts"
```

---

### Task 4: Новые дефолтные тексты промтов

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/RoleDefaults.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift`

- [ ] **Step 1: Обновить StageTemplateDefaults**

В `StageTemplateDefaults.content(for:)` заменить `userPromptTemplate` для четырёх кейсов. Тексты скопировать ДОСЛОВНО из spec `docs/superpowers/specs/2026-07-02-prompt-cascade-templates-design.md`, разделы:

- `.structure` ← «StageTemplate `structure` (шаги 3+4)»
- `.draft` ← «StageTemplate `draft` (шаги 5+6)»
- `.factCheck` ← «StageTemplate `factCheck` (шаг 7)»
- `.finalReview` ← «StageTemplate `finalReview` (шаг 8)»

`systemPrompt` у всех четырёх остаётся `""`. Кейсы `.productBlocks`, `.semanticsInText`, `.seoCheck` не трогать. Внутри Swift-строк `"""..."""` экранировать обратные кавычки не нужно, но следить за интерполяцией: в текстах промтов нет `\(`, поэтому обычные многострочные литералы подходят.

- [ ] **Step 2: Обновить RoleDefaults**

В `RoleDefaults.all` для роли `author` заменить `mandate` текстом из раздела спеки «Роль `author` — mandate».

В `ContextBlockDefaults.all` заменить `text`:
- для key `editorialPolicy` — текст из раздела «ContextBlock `editorialPolicy`»;
- для key `sources` — текст из раздела «ContextBlock `sources`».

Блок `seoGuidelines` не трогать.

- [ ] **Step 3: Добавить пресет «Сократить»**

В `SkillPresetDefaults.all` добавить последним элементом:

```swift
SkillPresetDefault(
    key: "shorten",
    name: "Сократить",
    prompt: "Сократи фрагмент: оставь только самое важное для пациента, который выбирает клинику. Убери повторы, необязательные подробности и «воду». Сохрани все факты и смысл, ничего не выдумывай.",
    roleKey: "editor"
),
```

- [ ] **Step 4: Прогнать затронутые тесты**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/StageTemplateSeederTests -only-testing:SEOContentCreatorTests/SkillPresetSeederTests -only-testing:SEOContentCreatorTests/PromptBuilderTests
```

Ожидание: PASS. Если какой-то тест проверяет старый текст дефолта дословно — обновить ожидание теста под новый текст (это единственная допустимая правка тестов здесь).

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift SEOContentCreator/SEOContentCreator/Logic/RoleDefaults.swift SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift
git commit -m "Adopt prompt cascade default texts"
```

---

### Task 5: Миграция v3 — доставка в существующую базу

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/TemplatesMigrationV3Tests.swift`

- [ ] **Step 1: Написать падающие тесты**

Создать `SEOContentCreator/SEOContentCreatorTests/TemplatesMigrationV3Tests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct TemplatesMigrationV3Tests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StageTemplate.self, ContextBlock.self, AIRole.self,
                 ImagePromptTemplate.self, ImageStylePreset.self, SkillPreset.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "migration-test-\(UUID().uuidString)")!
    }

    @Test func overwritesCascadeTemplatesAndBlocks() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let oldDraft = StageTemplate(stage: .draft, systemPrompt: "старый system", userPromptTemplate: "старый user")
        let oldSeoCheck = StageTemplate(stage: .seoCheck, systemPrompt: "", userPromptTemplate: "правленный seoCheck")
        context.insert(oldDraft)
        context.insert(oldSeoCheck)
        context.insert(ContextBlock(key: "editorialPolicy", title: "Редполитика", text: "старая редполитика"))
        context.insert(AIRole(key: "author", name: "ИИ-автор", mandate: "старый mandate", blockKeys: ["editorialPolicy", "sources"]))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(oldDraft.userPromptTemplate == StageTemplateDefaults.content(for: .draft).userPromptTemplate)
        #expect(oldSeoCheck.userPromptTemplate == "правленный seoCheck")

        let blocks = try context.fetch(FetchDescriptor<ContextBlock>())
        let policy = blocks.first { $0.key == "editorialPolicy" }
        #expect(policy?.text.contains("инфостиль") == true || policy?.text.contains("Инфостиль") == true || policy?.text.contains("Один абзац") == true)

        let roles = try context.fetch(FetchDescriptor<AIRole>())
        let author = roles.first { $0.key == "author" }
        #expect(author?.mandate.contains("Т—Ж") == true)
    }

    @Test func addsShortenPresetForExistingInstalls() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        context.insert(SkillPreset(name: "Мой скилл", prompt: "x", roleKey: "editor", order: 0))

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.contains { $0.defaultKey == "shorten" })
        #expect(presets.contains { $0.name == "Мой скилл" })
    }

    @Test func migrationRunsOnce() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)
        let draft = try context.fetch(FetchDescriptor<StageTemplate>()).first { $0.stageRaw == PipelineStage.draft.rawValue }
        draft?.userPromptTemplate = "правка пользователя после миграции"

        StageTemplateSeeder.seedIfNeeded(in: context, defaults: defaults)

        #expect(draft?.userPromptTemplate == "правка пользователя после миграции")
    }
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TemplatesMigrationV3Tests
```

Ожидание: FAIL — `overwritesCascadeTemplatesAndBlocks` и `addsShortenPresetForExistingInstalls` падают (миграции v3 нет; старая v2-миграция перезаписывает только systemPrompt).

- [ ] **Step 3: Реализовать миграцию v3**

В `SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift`:

1. `currentTemplatesDefaultsVersion` поднять с `2` до `3`.
2. Заменить метод `migrateStageTemplateSystemPromptsIfNeeded` на:

```swift
@MainActor
private static func migrateTemplatesIfNeeded(
    in context: ModelContext,
    defaults: UserDefaults
) {
    let storedVersion = defaults.integer(forKey: templatesDefaultsVersionKey)
    guard storedVersion < currentTemplatesDefaultsVersion else { return }

    // v3: доставка каскада промтов пользователя (spec 2026-07-02).
    let cascadeStages: Set<String> = [
        PipelineStage.structure.rawValue,
        PipelineStage.draft.rawValue,
        PipelineStage.factCheck.rawValue,
        PipelineStage.finalReview.rawValue
    ]
    let templates = (try? context.fetch(FetchDescriptor<StageTemplate>())) ?? []
    for template in templates {
        guard let stage = template.stage, cascadeStages.contains(template.stageRaw) else { continue }
        let content = StageTemplateDefaults.content(for: stage)
        template.systemPrompt = content.systemPrompt
        template.userPromptTemplate = content.userPromptTemplate
        template.updatedAt = .now
    }

    let migratedBlockKeys: Set<String> = ["editorialPolicy", "sources"]
    let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
    for block in blocks where migratedBlockKeys.contains(block.key) {
        if let def = ContextBlockDefaults.defaultForKey(block.key) {
            block.text = def.text
        }
    }

    let roles = (try? context.fetch(FetchDescriptor<AIRole>())) ?? []
    if let author = roles.first(where: { $0.key == "author" }),
       let def = RoleDefaults.defaultForKey("author") {
        author.mandate = def.mandate
    }

    let presets = (try? context.fetch(FetchDescriptor<SkillPreset>())) ?? []
    if !presets.contains(where: { $0.defaultKey == "shorten" }),
       let def = SkillPresetDefaults.all.first(where: { $0.key == "shorten" }) {
        let nextOrder = (presets.map(\.order).max() ?? -1) + 1
        context.insert(SkillPresetDefaults.make(def, order: nextOrder))
    }

    defaults.set(currentTemplatesDefaultsVersion, forKey: templatesDefaultsVersionKey)
}
```

3. В `seedIfNeeded` заменить вызов `migrateStageTemplateSystemPromptsIfNeeded(in:defaults:)` на `migrateTemplatesIfNeeded(in:defaults:)`.

Замечание: старая v2-логика (перезапись systemPrompt всех этапов) поглощается v3 для каскадных этапов; для остальных этапов systemPrompt и так `""` в дефолтах — отдельная ветка не нужна.

- [ ] **Step 4: Прогнать тесты**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS' -only-testing:SEOContentCreatorTests/TemplatesMigrationV3Tests -only-testing:SEOContentCreatorTests/StageTemplateSeederTests
```

Ожидание: PASS.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift SEOContentCreator/SEOContentCreatorTests/TemplatesMigrationV3Tests.swift
git commit -m "Migrate templates to prompt cascade v3"
```

---

### Task 6: UI — раздел «Запрещённые формулировки» в Шаблонах

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ForbiddenPhraseEditorView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`

- [ ] **Step 1: Создать редактор**

Создать `SEOContentCreator/SEOContentCreator/Views/Templates/ForbiddenPhraseEditorView.swift` (по образцу `ProductBlockEditorView`: @Bindable, локальные @State, кнопки «Сохранить»/«Удалить» с подтверждением деструктивного действия):

```swift
import SwiftUI
import SwiftData

struct ForbiddenPhraseEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var phrase: ForbiddenPhrase
    var onDelete: () -> Void

    @State private var phraseText = ""
    @State private var problemText = ""
    @State private var replacementText = ""
    @State private var savedNote: String?
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Запрещённая формулировка").font(.title2).bold()

                Text("Формулировка (как нельзя)").font(.headline)
                TextEditor(text: $phraseText).frame(minHeight: 60).border(.gray.opacity(0.3))

                Text("В чём проблема").font(.headline)
                TextEditor(text: $problemText).frame(minHeight: 60).border(.gray.opacity(0.3))

                Text("Как можно заменить").font(.headline)
                TextEditor(text: $replacementText).frame(minHeight: 60).border(.gray.opacity(0.3))

                HStack {
                    Button("Сохранить") { save() }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Удалить", role: .destructive) { confirmingDelete = true }
                    if let savedNote { Text(savedNote).font(.caption).foregroundStyle(.green) }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear(perform: load)
        .confirmationDialog(
            "Удалить формулировку «\(phrase.phrase)»?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { deletePhrase() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func load() {
        phraseText = phrase.phrase
        problemText = phrase.problem
        replacementText = phrase.replacement
    }

    private func save() {
        phrase.phrase = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.problem = problemText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.replacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        phrase.updatedAt = .now
        try? context.save()
        savedNote = "Сохранено"
    }

    private func deletePhrase() {
        context.delete(phrase)
        try? context.save()
        onDelete()
    }
}
```

- [ ] **Step 2: Встроить в TemplatesView**

В `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`:

1. В enum `TemplateSelection` добавить кейс `case forbiddenPhrase(UUID)`.
2. Добавить `@Query private var forbiddenPhrases: [ForbiddenPhrase]` и сортировку:

```swift
private var sortedForbiddenPhrases: [ForbiddenPhrase] {
    forbiddenPhrases.sorted { $0.order < $1.order }
}
```

3. Добавить computed `selectedForbiddenPhrase` по образцу соседей:

```swift
private var selectedForbiddenPhrase: ForbiddenPhrase? {
    guard case .forbiddenPhrase(let id) = selection else { return nil }
    return forbiddenPhrases.first { $0.uuid == id }
}
```

4. В `List` после секции «Подсказки» добавить секцию:

```swift
Section("Запрещённые формулировки") {
    ForEach(sortedForbiddenPhrases) { phrase in
        Text(phrase.phrase).lineLimit(1)
            .tag(TemplateSelection.forbiddenPhrase(phrase.uuid))
    }
    Button {
        let next = (forbiddenPhrases.map(\.order).max() ?? -1) + 1
        let phrase = ForbiddenPhrase(phrase: "Новая формулировка", problem: "", replacement: "", order: next)
        context.insert(phrase)
        selection = .forbiddenPhrase(phrase.uuid)
    } label: {
        Label("Добавить формулировку", systemImage: "plus")
    }
}
```

5. В `detail` добавить ветку перед `else`:

```swift
} else if let phrase = selectedForbiddenPhrase {
    ForbiddenPhraseEditorView(phrase: phrase) { selection = nil }.id(phrase.uuid)
```

6. Добавить `.onChange(of: forbiddenPhrases.map(\.uuid)) { _, _ in ensureSelection() }` рядом с остальными.

- [ ] **Step 3: Сборка**

```bash
cd SEOContentCreator && xcodebuild build -scheme SEOContentCreator -destination 'platform=macOS'
```

Ожидание: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/Templates/ForbiddenPhraseEditorView.swift SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "Edit forbidden phrases in templates"
```

---

### Task 7: Финальная проверка и handoff

**Files:**
- Modify: `ai/current-task.md`

- [ ] **Step 1: Полный прогон тестов**

```bash
cd SEOContentCreator && xcodebuild test -scheme SEOContentCreator -destination 'platform=macOS'
```

Ожидание: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Проверка защищённых файлов**

```bash
git diff --name-only main...HEAD
```

Ожидание: только файлы из File Map этого плана + docs/superpowers/* + ai/current-task.md. Защищённые architecture-файлы не тронуты.

- [ ] **Step 3: Обновить handoff в ai/current-task.md**

Записать: Stage: review; что сделано (дефолты, миграция v3, ForbiddenPhrase + UI, пресет shorten); что ручная проверка UI и реального прогона каскада не выполнялась — предложить вынести в future task при task-finish.

- [ ] **Step 4: Commit**

```bash
git add ai/current-task.md
git commit -m "Update prompt cascade task handoff"
```

---

## Self-Review

Spec coverage:
- Тексты промтов 4 этапов — Task 4 (источник: spec).
- Блоки editorialPolicy/sources — Task 4 + миграция Task 5.
- Mandate автора (Т—Ж) — Task 4 + Task 5.
- Пресет «Сократить» — Task 4 (дефолты) + Task 5 (доставка существующим).
- ForbiddenPhrase модель/сидер/рендерер — Task 1.
- Плейсхолдер и подстановка — Task 2 + Task 3.
- UI таблицы — Task 6.
- Миграция v3 и её идемпотентность — Task 5.
- Тесты — Tasks 1, 2, 5; сборка UI — Task 6.

Type consistency: `ForbiddenPhrase(phrase:problem:replacement:order:)` одинаков в Tasks 1, 5 (тестовый контейнер не нуждается в модели — миграционный тест её не использует), 6. `ForbiddenPhraseRenderer.render(_:)` — Tasks 1, 3. Параметр `forbiddenPhrases: String = ""` — Tasks 2, 3.

Scope: реальный прогон каскада на живой теме и ручная проверка UI — вне плана (по образцу прошлой задачи — future task).
