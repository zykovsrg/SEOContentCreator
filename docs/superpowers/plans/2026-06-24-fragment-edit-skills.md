# Fragment Edit — Skills + Regeneration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать редактору два инструмента ручной правки выделенного фрагмента — применение пресета-скилла и регенерацию по комментарию — с предпросмотром side-by-side и созданием новой версии при приёме.

**Architecture:** Пользователь копирует фрагмент в одно окно «Правка фрагмента» (поле подставляется из буфера). ИИ переписывает только фрагмент; чистая функция `FragmentSplicer` вставляет результат в полный текст текущей версии (с проверкой уникальности), затем показывается side-by-side и приём создаёт `ArticleVersion`. Пресеты скиллов — новая SwiftData-сущность, редактируемая в «Шаблонах»; роли берутся из существующей системы `AIRole` + `RoleContextAssembler`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`, `@Test`, `#expect`). OpenAI-стриминг через существующий `OpenAIClient`/`StreamProvider`.

**Команды проверки:**
- Компиляция (приложение + тесты):
  `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
  Ожидаемо: `** TEST BUILD SUCCEEDED **`.
- Прогон тестов: **Cmd+U в Xcode** (CLI `xcodebuild test` в этом окружении зависает — особенность среды, см. память проекта). После реализации все юнит-тесты должны быть зелёными.

**Соглашение о коммитах:** `Plan Task <N>: <короткое действие>` (по `ai/decisions.md` 2026-05-17).

---

## Карта файлов

**Новые:**
- `SEOContentCreator/SEOContentCreator/Models/SkillPreset.swift` — `@Model` пресета скилла.
- `SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift` — 4 стартовых скилла.
- `SEOContentCreator/SEOContentCreator/Logic/SkillPresetSeeder.swift` — засев при старте.
- `SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift` — чистая замена фрагмента.
- `SEOContentCreator/SEOContentCreator/Logic/FragmentPromptBuilder.swift` — чистая сборка промта.
- `SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift` — `@Observable` стриминг + сплайс + версия.
- `SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift` — окно правки фрагмента.
- `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift` — тесты юнитов.

**Изменяемые:**
- `SEOContentCreator/SEOContentCreator/Models/VersionSource.swift` — два новых кейса.
- `SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift` — `stageTitle` для новых меток.
- `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift` — регистрация `SkillPreset` в схеме.
- `SEOContentCreator/SEOContentCreator/Views/RootView.swift` — вызов `SkillPresetSeeder`.
- `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift` — кнопка тулбара + окно.
- `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` — раздел «Скиллы».

> **Важно:** при добавлении нового `.swift`-файла он должен попасть в target. В этом проекте файлы добавляются в группу через Xcode (PBX). Если работаете из CLI — после создания файла откройте проект в Xcode и убедитесь, что файл в target `SEOContentCreator` (для исходников) или `SEOContentCreatorTests` (для тестов), иначе `build-for-testing` его не увидит.

---

## Task 1: Новые источники версий

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Models/VersionSource.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift:60-68`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Создать тестовый файл с проверкой заголовков**

Создать `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`:

```swift
import Testing
import SwiftData
@testable import SEOContentCreator

struct VersionSourceFragmentTests {
    @Test func skillAppliedTitle() {
        #expect(VersionSource.skillApplied.title == "Правка скиллом")
    }

    @Test func fragmentRegeneratedTitle() {
        #expect(VersionSource.fragmentRegenerated.title == "Регенерация фрагмента")
    }
}
```

- [ ] **Step 2: Скомпилировать тесты — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `type 'VersionSource' has no member 'skillApplied'`.

- [ ] **Step 3: Добавить кейсы в VersionSource**

В `Models/VersionSource.swift` добавить в `enum` после `case checkApplied`:

```swift
    case skillApplied
    case fragmentRegenerated
```

И в `var title` добавить ветки перед закрытием `switch`:

```swift
        case .skillApplied:        return "Правка скиллом"
        case .fragmentRegenerated: return "Регенерация фрагмента"
```

- [ ] **Step 4: Расширить ArticleVersion.stageTitle для новых меток**

В `Models/ArticleVersion.swift` в `var stageTitle`, в `switch stageRaw` добавить ветки перед `default`:

```swift
        case "skillApplied":        return "Правка скиллом"
        case "fragmentRegenerated": return "Регенерация фрагмента"
```

- [ ] **Step 5: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 6: Прогнать тесты в Xcode (Cmd+U)** — `VersionSourceFragmentTests` зелёные.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/VersionSource.swift \
        SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 1: add skillApplied/fragmentRegenerated version sources"
```

---

## Task 2: Модель SkillPreset + стартовые скиллы

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/SkillPreset.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Написать падающий тест на дефолты**

Добавить в `FragmentEditTests.swift`:

```swift
struct SkillPresetDefaultsTests {
    @Test func providesFourStarterSkills() {
        #expect(SkillPresetDefaults.all.count == 4)
    }

    @Test func everyDefaultHasNamePromptAndKnownRole() {
        let knownRoles: Set<String> = ["author", "seo", "factChecker", "editor"]
        for preset in SkillPresetDefaults.all {
            #expect(!preset.name.isEmpty)
            #expect(!preset.prompt.isEmpty)
            #expect(knownRoles.contains(preset.roleKey))
        }
    }

    @Test func makeAllAssignsIncreasingOrder() {
        let presets = SkillPresetDefaults.makeAll()
        #expect(presets.map(\.order) == Array(0..<presets.count))
    }
}
```

- [ ] **Step 2: Скомпилировать — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `cannot find 'SkillPresetDefaults' in scope`.

- [ ] **Step 3: Создать модель SkillPreset**

`Models/SkillPreset.swift`:

```swift
import Foundation
import SwiftData

@Model
final class SkillPreset {
    var uuid: UUID
    var name: String
    var prompt: String
    /// AIRole.key: "author" / "seo" / "factChecker" / "editor".
    var roleKey: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(name: String, prompt: String, roleKey: String, order: Int) {
        self.uuid = UUID()
        self.name = name
        self.prompt = prompt
        self.roleKey = roleKey
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Создать дефолты**

`Logic/SkillPresetDefaults.swift`:

```swift
import Foundation

struct SkillPresetDefault {
    let name: String
    let prompt: String
    let roleKey: String
}

enum SkillPresetDefaults {
    static let all: [SkillPresetDefault] = [
        SkillPresetDefault(
            name: "Переписать в инфостиле",
            prompt: "Перепиши фрагмент в инфостиле: коротко, ясно, без воды и канцелярита. Сохрани смысл и все факты, ничего не выдумывай.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Упростить",
            prompt: "Упрости фрагмент: сделай предложения короче и понятнее для пациента. Сохрани смысл и все факты.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Уточнить",
            prompt: "Сделай фрагмент точнее и конкретнее, убери размытые формулировки. Не добавляй новых фактов, которых нет в исходном тексте.",
            roleKey: "editor"
        ),
        SkillPresetDefault(
            name: "Убрать канцелярит",
            prompt: "Убери из фрагмента канцелярит и штампы, сделай язык живым и точным. Сохрани смысл и все факты.",
            roleKey: "editor"
        )
    ]

    static func make(_ def: SkillPresetDefault, order: Int) -> SkillPreset {
        SkillPreset(name: def.name, prompt: def.prompt, roleKey: def.roleKey, order: order)
    }

    static func makeAll() -> [SkillPreset] {
        all.enumerated().map { make($0.element, order: $0.offset) }
    }
}
```

- [ ] **Step 5: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 6: Прогнать тесты (Cmd+U)** — `SkillPresetDefaultsTests` зелёные.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/SkillPreset.swift \
        SEOContentCreator/SEOContentCreator/Logic/SkillPresetDefaults.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 2: SkillPreset model + starter skill defaults"
```

---

## Task 3: Сидер + регистрация в схеме

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/SkillPresetSeeder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift:10-16`
- Modify: `SEOContentCreator/SEOContentCreator/Views/RootView.swift:21-24`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Написать падающий тест на сидер**

Добавить в `FragmentEditTests.swift`:

```swift
@MainActor
struct SkillPresetSeederTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SkillPreset.self, configurations: config)
        return ModelContext(container)
    }

    @Test func seedsDefaultsIntoEmptyStore() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.count == SkillPresetDefaults.all.count)
    }

    @Test func isIdempotent() throws {
        let context = try makeContext()
        SkillPresetSeeder.seedIfNeeded(in: context)
        SkillPresetSeeder.seedIfNeeded(in: context)
        let presets = try context.fetch(FetchDescriptor<SkillPreset>())
        #expect(presets.count == SkillPresetDefaults.all.count)
    }
}
```

- [ ] **Step 2: Скомпилировать — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `cannot find 'SkillPresetSeeder' in scope`.

- [ ] **Step 3: Создать сидер**

`Logic/SkillPresetSeeder.swift`:

```swift
import Foundation
import SwiftData

enum SkillPresetSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<SkillPreset>())) ?? []
        guard existing.isEmpty else { return }
        for preset in SkillPresetDefaults.makeAll() {
            context.insert(preset)
        }
    }
}
```

- [ ] **Step 4: Зарегистрировать SkillPreset в схеме**

В `SEOContentCreatorApp.swift` в массиве `.modelContainer(for:)` добавить `SkillPreset.self` в конец списка (после `EditorDictionary.self`):

```swift
            ExternalDocument.self, EditorDictionary.self, SkillPreset.self
```

- [ ] **Step 5: Вызвать сидер при старте**

В `Views/RootView.swift` в `.task { ... }` добавить строку после `EditorDictionarySeeder.seedIfNeeded(in: context)`:

```swift
            SkillPresetSeeder.seedIfNeeded(in: context)
```

- [ ] **Step 6: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 7: Прогнать тесты (Cmd+U)** — `SkillPresetSeederTests` зелёные.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/SkillPresetSeeder.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift \
        SEOContentCreator/SEOContentCreator/Views/RootView.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 3: SkillPreset seeder + schema registration + startup seed"
```

---

## Task 4: FragmentSplicer (чистая замена)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Написать падающие тесты**

Добавить в `FragmentEditTests.swift`:

```swift
struct FragmentSplicerTests {
    @Test func replacesUniqueFragment() {
        let result = FragmentSplicer.splice(
            fullText: "Начало. Старый кусок. Конец.",
            fragment: "Старый кусок.",
            replacement: "Новый кусок."
        )
        #expect(result == .replaced("Начало. Новый кусок. Конец."))
    }

    @Test func notFoundWhenMissing() {
        let result = FragmentSplicer.splice(
            fullText: "Текст без фрагмента.",
            fragment: "чего тут нет",
            replacement: "X"
        )
        #expect(result == .notFound)
    }

    @Test func notFoundWhenFragmentEmpty() {
        let result = FragmentSplicer.splice(fullText: "Любой текст.", fragment: "", replacement: "X")
        #expect(result == .notFound)
    }

    @Test func ambiguousWhenMultipleMatches() {
        let result = FragmentSplicer.splice(
            fullText: "Повтор. Повтор.",
            fragment: "Повтор.",
            replacement: "X"
        )
        #expect(result == .ambiguous(2))
    }

    @Test func whitespaceSensitiveMatch() {
        // Лишний пробел в искомом фрагменте → совпадения нет.
        let result = FragmentSplicer.splice(
            fullText: "Раз два три.",
            fragment: "Раз  два",
            replacement: "X"
        )
        #expect(result == .notFound)
    }
}
```

- [ ] **Step 2: Скомпилировать — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `cannot find 'FragmentSplicer' in scope`.

- [ ] **Step 3: Реализовать FragmentSplicer**

`Logic/FragmentSplicer.swift`:

```swift
import Foundation

enum FragmentSplicer {
    enum Result: Equatable {
        case replaced(String)
        case notFound
        case ambiguous(Int)
    }

    /// Replaces the fragment in the full text only when it occurs exactly once.
    static func splice(fullText: String, fragment: String, replacement: String) -> Result {
        guard !fragment.isEmpty else { return .notFound }
        let count = occurrences(of: fragment, in: fullText)
        switch count {
        case 0:
            return .notFound
        case 1:
            return .replaced(fullText.replacingOccurrences(of: fragment, with: replacement))
        default:
            return .ambiguous(count)
        }
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
```

- [ ] **Step 4: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Прогнать тесты (Cmd+U)** — `FragmentSplicerTests` зелёные.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 4: FragmentSplicer with uniqueness check"
```

---

## Task 5: FragmentPromptBuilder (чистая сборка промта)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/FragmentPromptBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Написать падающие тесты**

Добавить в `FragmentEditTests.swift`:

```swift
struct FragmentPromptBuilderTests {
    @Test func systemComesFromRoleContext() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "Ты — ИИ-редактор.",
            instruction: "Упрости.",
            fragment: "Сложный фрагмент."
        )
        #expect(prompt.system == "Ты — ИИ-редактор.")
    }

    @Test func userContainsInstructionAndFragment() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "роль",
            instruction: "Упрости фрагмент.",
            fragment: "Сложный фрагмент."
        )
        #expect(prompt.user.contains("Упрости фрагмент."))
        #expect(prompt.user.contains("Сложный фрагмент."))
    }

    @Test func userAsksForFragmentOnly() {
        let prompt = FragmentPromptBuilder().build(
            roleContext: "роль",
            instruction: "Упрости.",
            fragment: "Текст."
        )
        #expect(prompt.user.contains("только переписанный фрагмент"))
    }
}
```

- [ ] **Step 2: Скомпилировать — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `cannot find 'FragmentPromptBuilder' in scope`.

- [ ] **Step 3: Реализовать FragmentPromptBuilder**

`Logic/FragmentPromptBuilder.swift`:

```swift
import Foundation

struct FragmentPromptBuilder {
    func build(roleContext: String, instruction: String, fragment: String) -> (system: String, user: String) {
        let system = roleContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = """
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))

        Вот фрагмент текста:
        \(fragment)

        Верни только переписанный фрагмент, без пояснений, кавычек и заголовков.
        """
        return (system, user)
    }
}
```

- [ ] **Step 4: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Прогнать тесты (Cmd+U)** — `FragmentPromptBuilderTests` зелёные.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/FragmentPromptBuilder.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 5: FragmentPromptBuilder"
```

---

## Task 6: FragmentEditor (стриминг + сплайс + версия)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift`

- [ ] **Step 1: Написать падающие тесты с мок-провайдером**

Добавить в `FragmentEditTests.swift`:

```swift
@MainActor
struct FragmentEditorTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Topic.self, ArticleVersion.self, GenerationJob.self,
            AIRole.self, ContextBlock.self, SkillPreset.self,
            configurations: config
        )
    }

    private func tokenStream(_ text: String) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token(text))
                continuation.yield(.finish("stop"))
                continuation.finish()
            }
        }
    }

    private func errorStream() -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "test", code: 1))
            }
        }
    }

    @Test func successProducesProposedTextAndAcceptCreatesVersion() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: tokenStream("Новый кусок."), keyProvider: { "key" })
        await editor.run(
            fullText: "Начало. Старый кусок. Конец.",
            fragment: "Старый кусок.",
            instruction: "Упрости.",
            source: .skillApplied,
            roleKey: "editor",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            topic: topic,
            in: context
        )

        #expect(editor.proposedText == "Начало. Новый кусок. Конец.")
        #expect(editor.lastErrorMessage == nil)

        editor.accept(topic: topic, in: context)
        let versions = try context.fetch(FetchDescriptor<ArticleVersion>())
        #expect(versions.count == 1)
        #expect(versions.first?.text == "Начало. Новый кусок. Конец.")
        #expect(versions.first?.source == .skillApplied)
        #expect(topic.currentVersionID == versions.first?.uuid)
    }

    @Test func ambiguousFragmentSetsErrorAndNoProposedText() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: tokenStream("X"), keyProvider: { "key" })
        await editor.run(
            fullText: "Повтор. Повтор.",
            fragment: "Повтор.",
            instruction: "Упрости.",
            source: .skillApplied,
            roleKey: "editor",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            topic: topic,
            in: context
        )

        #expect(editor.proposedText == nil)
        #expect(editor.lastErrorMessage?.contains("2 раз") == true)
    }

    @Test func errorPathSurfacesMessage() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        context.insert(topic)

        let editor = FragmentEditor(streamProvider: errorStream(), keyProvider: { "key" })
        await editor.run(
            fullText: "Текст. Кусок. Конец.",
            fragment: "Кусок.",
            instruction: "Упрости.",
            source: .fragmentRegenerated,
            roleKey: "author",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 4000,
            topic: topic,
            in: context
        )

        #expect(editor.proposedText == nil)
        #expect(editor.lastErrorMessage != nil)
    }
}
```

> Примечание: проверьте сигнатуру `Topic.init`. Если она отличается от `Topic(title:articleType:)`, используйте фактический инициализатор из `Models/Topic.swift` во всех трёх тестах.

- [ ] **Step 2: Скомпилировать — убедиться, что не собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: FAIL — `cannot find 'FragmentEditor' in scope`.

- [ ] **Step 3: Реализовать FragmentEditor**

`Logic/FragmentEditor.swift`:

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class FragmentEditor {
    typealias StreamProvider = StageExecutor.StreamProvider
    typealias KeyProvider = () throws -> String

    var streamingText: String = ""
    var isRunning: Bool = false
    var lastErrorMessage: String?
    var lastWarningMessage: String?
    /// Spliced full text awaiting accept/reject; nil until a successful run.
    var proposedText: String?

    private(set) var proposedSource: VersionSource = .skillApplied
    private(set) var agentName: String?

    private let streamProvider: StreamProvider
    private let keyProvider: KeyProvider

    init(streamProvider: @escaping StreamProvider, keyProvider: @escaping KeyProvider) {
        self.streamProvider = streamProvider
        self.keyProvider = keyProvider
    }

    static func live() -> FragmentEditor {
        FragmentEditor(
            streamProvider: { apiKey, system, user, model, temperature, maxTokens, reasoningEffort in
                OpenAIClient().streamCompletion(
                    apiKey: apiKey, system: system, user: user,
                    model: model, temperature: temperature, maxTokens: maxTokens,
                    reasoningEffort: reasoningEffort
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() }
        )
    }

    func run(
        fullText: String,
        fragment: String,
        instruction: String,
        source: VersionSource,
        roleKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        topic: Topic,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        proposedText = nil
        proposedSource = source

        let role = fetchRole(roleKey, in: context)
        let name = role?.name ?? "ИИ"
        agentName = name
        let job = GenerationJob(stageLabel: source.rawValue, agentName: name, modelName: model)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(role, in: context)
            let prompt = FragmentPromptBuilder().build(
                roleContext: roleContext, instruction: instruction, fragment: fragment
            )
            var collected = ""
            var truncated = false
            for try await event in streamProvider(
                key, prompt.system, prompt.user, model, temperature, maxTokens, nil
            ) {
                switch event {
                case .token(let t):
                    collected += t
                    streamingText = collected
                case .finish(let reason):
                    if reason == "length" { truncated = true }
                }
            }
            if truncated {
                lastWarningMessage = "Ответ оборван по лимиту токенов. Текст может быть неполным — увеличьте max tokens в разделе «Шаблоны»."
            }

            let rewritten = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            switch FragmentSplicer.splice(fullText: fullText, fragment: fragment, replacement: rewritten) {
            case .replaced(let newText):
                proposedText = newText
                job.status = .success
                job.finishedAt = .now
            case .notFound:
                lastErrorMessage = "Фрагмент не найден в тексте — проверьте, что скопировали его точно."
                job.status = .error
                job.finishedAt = .now
            case .ambiguous(let count):
                lastErrorMessage = "Фрагмент встречается \(count) раз — расширьте выделение, чтобы он был уникальным."
                job.status = .error
                job.finishedAt = .now
            }
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            job.status = .error
            job.finishedAt = .now
            lastErrorMessage = message
        }

        isRunning = false
    }

    func accept(topic: Topic, in context: ModelContext) {
        guard let text = proposedText else { return }
        let version = ArticleVersion(
            stageLabel: proposedSource.rawValue, source: proposedSource,
            text: text, agentName: agentName
        )
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
        proposedText = nil
    }

    private func fetchRole(_ key: String, in context: ModelContext) -> AIRole? {
        let descriptor = FetchDescriptor<AIRole>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first
    }

    private func buildRoleContext(_ role: AIRole?, in context: ModelContext) -> String {
        guard let role else { return "" }
        let blocks = (try? context.fetch(FetchDescriptor<ContextBlock>())) ?? []
        return RoleContextAssembler.assemble(role: role, blocks: blocks)
    }
}
```

> Примечание: если поле `Topic.currentVersionID` называется иначе, сверьтесь с `Models/Topic.swift` (в `TopicWorkspaceView` используется `topic.currentVersionID`).

- [ ] **Step 4: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Прогнать тесты (Cmd+U)** — `FragmentEditorTests` зелёные.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift \
        SEOContentCreator/SEOContentCreatorTests/FragmentEditTests.swift
git commit -m "Plan Task 6: FragmentEditor — stream, splice, create version on accept"
```

---

## Task 7: FragmentEditSheet (окно правки фрагмента)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift`

Тестов на сам View нет (SwiftUI-вёрстка), проверка — компиляция + ручной smoke в Task 9 после подключения тулбара. Логика уже покрыта в Task 4–6.

- [ ] **Step 1: Создать окно**

`Views/FragmentEditSheet.swift`:

```swift
import SwiftUI
import SwiftData
import AppKit

private enum FragmentMode: String, CaseIterable, Identifiable {
    case skill
    case comment
    var id: String { rawValue }
    var title: String { self == .skill ? "Скилл" : "Свой комментарий" }
}

struct FragmentEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @Query(sort: \SkillPreset.order) private var skills: [SkillPreset]

    @State private var mode: FragmentMode = .skill
    @State private var fragment = ""
    @State private var comment = ""
    @State private var selectedSkillID: UUID?
    @State private var editor = FragmentEditor.live()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Правка фрагмента").font(.headline)

            if editor.proposedText == nil {
                inputForm
            } else {
                preview
            }
        }
        .padding()
        .frame(width: 720, height: 560)
        .onAppear(perform: prefillFromClipboard)
    }

    // MARK: Input

    @ViewBuilder private var inputForm: some View {
        Picker("Режим", selection: $mode) {
            ForEach(FragmentMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        Text("Фрагмент").font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $fragment)
            .frame(minHeight: 90)
            .border(Color.secondary.opacity(0.3))

        if mode == .skill {
            Text("Скилл").font(.caption).foregroundStyle(.secondary)
            List(selection: $selectedSkillID) {
                ForEach(skills) { skill in
                    Text(skill.name).tag(Optional(skill.uuid))
                }
            }
            .frame(minHeight: 140)
        } else {
            Text("Что не нравится").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $comment)
                .frame(minHeight: 90)
                .border(Color.secondary.opacity(0.3))
        }

        if let error = editor.lastErrorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        }

        HStack {
            Button("Отмена") { dismiss() }
            Spacer()
            if editor.isRunning {
                ProgressView().controlSize(.small)
            }
            Button("Применить", action: run)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
        }
    }

    private var canRun: Bool {
        guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(editor.isRunning) else { return false }
        switch mode {
        case .skill:   return selectedSkillID != nil
        case .comment: return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        SideBySideView(
            leftText: topic.currentVersion?.text,
            rightText: editor.proposedText,
            isStreaming: false
        )
        .border(Color.secondary.opacity(0.2))

        HStack {
            Button("Отклонить", role: .destructive) { editor.proposedText = nil }
            Spacer()
            Button("Принять") {
                editor.accept(topic: topic, in: context)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Actions

    private func prefillFromClipboard() {
        if fragment.isEmpty, let clip = NSPasteboard.general.string(forType: .string) {
            fragment = clip
        }
    }

    private func run() {
        let fullText = topic.currentVersion?.text ?? ""
        let (instruction, source, roleKey): (String, VersionSource, String)
        switch mode {
        case .skill:
            guard let skill = skills.first(where: { $0.uuid == selectedSkillID }) else { return }
            instruction = skill.prompt
            source = .skillApplied
            roleKey = skill.roleKey
        case .comment:
            instruction = "Перепиши фрагмент с учётом замечания: \(comment)"
            source = .fragmentRegenerated
            roleKey = "author"
        }
        Task {
            await editor.run(
                fullText: fullText, fragment: fragment, instruction: instruction,
                source: source, roleKey: roleKey, model: model,
                temperature: 0.6, maxTokens: 4000, topic: topic, in: context
            )
        }
    }
}
```

> Примечание: сверьте `topic.currentVersion?.text` — в `TopicWorkspaceView` используется именно `topic.currentVersion?.text`. Если `Topic` не имеет `currentVersion`, используйте тот же путь, что и рабочее пространство.

- [ ] **Step 2: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift
git commit -m "Plan Task 7: FragmentEditSheet — combined skill/comment fragment editor"
```

---

## Task 8: Кнопка в тулбаре рабочего пространства

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift:17-25` (новый `@State`), `:97-110` (новый `.sheet`), `:167-178` (новая кнопка тулбара)

- [ ] **Step 1: Добавить состояние показа окна**

В блоке `@State` (рядом с `@State private var showHints = false`) добавить:

```swift
    @State private var showFragmentEdit = false
```

- [ ] **Step 2: Добавить кнопку в тулбар**

В `toolbarContent`, после строки с кнопкой «Подсказки» (`showHints = true`), добавить:

```swift
        ToolbarItem { Button { showFragmentEdit = true } label: { Label("Правка фрагмента", systemImage: "wand.and.stars") } }
```

- [ ] **Step 3: Подключить окно**

Рядом с `.sheet(isPresented: $showHints) { SoftHintsSheet(topic: topic) }` добавить:

```swift
        .sheet(isPresented: $showFragmentEdit) { FragmentEditSheet(topic: topic) }
```

- [ ] **Step 4: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift
git commit -m "Plan Task 8: toolbar button + sheet for fragment edit"
```

---

## Task 9: Раздел «Скиллы» в «Шаблонах»

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` (новый кейс `TemplateSelection`, `@Query`, `Section`, ветка `detail`, редактор-подвью)

- [ ] **Step 1: Добавить кейс выбора и запрос**

В `private enum TemplateSelection` добавить кейс:

```swift
    case skill(UUID)
```

В `TemplatesView` рядом с другими `@Query` добавить:

```swift
    @Query private var skills: [SkillPreset]
```

И вычисляемое свойство сортировки рядом с `sortedImagePresets`:

```swift
    private var sortedSkills: [SkillPreset] {
        skills.sorted { $0.order < $1.order }
    }

    private var selectedSkill: SkillPreset? {
        guard case .skill(let id) = selection else { return nil }
        return skills.first { $0.uuid == id }
    }
```

- [ ] **Step 2: Добавить секцию в список**

В `List(selection: $selection)` после `Section("Подсказки") { ... }` добавить:

```swift
                Section("Скиллы") {
                    ForEach(sortedSkills) { skill in
                        Text(skill.name).tag(TemplateSelection.skill(skill.uuid))
                    }
                    Button {
                        let next = (skills.map(\.order).max() ?? -1) + 1
                        let preset = SkillPreset(name: "Новый скилл", prompt: "", roleKey: "editor", order: next)
                        context.insert(preset)
                        selection = .skill(preset.uuid)
                    } label: {
                        Label("Добавить скилл", systemImage: "plus")
                    }
                }
```

- [ ] **Step 3: Добавить ветку detail**

В `private var detail` цепочка устроена как `if let ... else if let ... else { ContentUnavailableView(...) }`. Вставьте ветку `selectedSkill` перед финальным `else`, после ветки `selectedEditorDictionary`:

```swift
        } else if let dict = selectedEditorDictionary {
            EditorDictionaryEditorView(dictionary: dict).id(dict.uuid)
        } else if let skill = selectedSkill {
            SkillEditorView(skill: skill).id(skill.uuid)
        } else {
            ContentUnavailableView("Выберите шаблон", systemImage: "doc.text")
        }
```

(Ветки `selectedEditorDictionary` и финальный `else` уже есть — добавляется только средняя ветка `selectedSkill`.)

Также добавьте в `ensureSelection()` ветку для скиллов (в конец цепочки `else if`), чтобы раздел открывался, если других шаблонов нет:

```swift
        } else if let first = sortedSkills.first {
            selection = .skill(first.uuid)
        }
```

- [ ] **Step 4: Добавить подвью редактора скилла**

В конец файла (рядом с другими `private struct ...EditorView`) добавить:

```swift
private struct SkillEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var skill: SkillPreset

    private let roleOptions: [(key: String, name: String)] = [
        ("editor", "ИИ-редактор"),
        ("author", "ИИ-автор"),
        ("seo", "ИИ-SEO")
    ]

    var body: some View {
        Form {
            TextField("Название", text: $skill.name)
            Picker("Роль", selection: $skill.roleKey) {
                ForEach(roleOptions, id: \.key) { Text($0.name).tag($0.key) }
            }
            Section("Промт") {
                TextEditor(text: $skill.prompt).frame(minHeight: 160)
            }
            HStack {
                Button("Сбросить к стандартному", action: reset)
                    .disabled(defaultForSkill == nil)
                Spacer()
                Button("Удалить", role: .destructive) { context.delete(skill) }
            }
        }
        .padding()
        .onChange(of: skill.name) { _, _ in skill.updatedAt = .now }
        .onChange(of: skill.prompt) { _, _ in skill.updatedAt = .now }
    }

    private var defaultForSkill: SkillPresetDefault? {
        SkillPresetDefaults.all.first { $0.name == skill.name }
    }

    private func reset() {
        guard let def = defaultForSkill else { return }
        skill.prompt = def.prompt
        skill.roleKey = def.roleKey
        skill.updatedAt = .now
    }
}
```

> Примечание о сбросе: «Сбросить к стандартному» сопоставляет скилл с дефолтом по названию. Если пользователь переименовал скилл, кнопка станет недоступна — это приемлемо для первой итерации (сброс рассчитан на стандартные скиллы). Сверьте сигнатуру `.onChange(of:)` с другими редакторами в `TemplatesView` (двухаргументная форma `{ _, _ in }` для macOS 14+).

- [ ] **Step 5: Скомпилировать — убедиться, что собирается**

Run: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -project SEOContentCreator/SEOContentCreator.xcodeproj -quiet`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 6: Ручной smoke (Cmd+R)**

Проверьте вживую:
1. «Шаблоны» → раздел «Скиллы»: видны 4 стартовых скилла; можно добавить, переименовать, изменить промт/роль, удалить, сбросить к стандартному.
2. Откройте тему с готовым текстом. Выделите фрагмент в статье, Cmd+C.
3. Тулбар → «Правка фрагмента»: поле фрагмента подставлено из буфера.
4. Режим «Скилл» → выбрать скилл → «Применить» → side-by-side → «Принять» создаёт новую версию (видно в «Версиях», источник «Правка скиллом»).
5. Режим «Свой комментарий» → ввести замечание → «Применить» → side-by-side → «Принять» (источник «Регенерация фрагмента»).
6. Проверка ошибок: вставьте в поле фрагмента текст, которого нет в статье → «Применить» → сообщение «фрагмент не найден». Вставьте фрагмент, который встречается дважды → сообщение «встречается N раз».

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift
git commit -m "Plan Task 9: «Скиллы» section in Templates (CRUD + reset)"
```

---

## Финал

- [ ] Полный прогон тестов в Xcode (Cmd+U) — все юнит-тесты зелёные, включая `FragmentEditTests`.
- [ ] `xcodebuild build-for-testing` — `** TEST BUILD SUCCEEDED **`.
- [ ] Ручной smoke по Task 9 Step 6 пройден.
- [ ] Предложить `task-finish`.

## Self-review (выполнено при написании плана)

- **Покрытие spec:** Вариант A (ручная вставка + буфер) — Task 7 `prefillFromClipboard`. Средняя модель пресета (название+промт+роль) — Task 2/9. Одно окно с переключателем — Task 7. Поток фрагмент→ИИ→сплайс→side-by-side→версия — Task 6/7. Замена с проверкой уникальности — Task 4. Роли (скилл — своя, регенерация — author) — Task 7 `run()`. Обработка ошибок (ключ/сеть/обрыв/notFound/ambiguous) — Task 6. Новая сущность в схеме + сидер — Task 2/3. Раздел «Скиллы» + сброс — Task 9. Новые `VersionSource` — Task 1. Все разделы spec имеют задачу.
- **Плейсхолдеры:** код приведён в каждом шаге; «примечания» указывают на сверку реальных сигнатур (`Topic.init`, `currentVersion`, `.onChange`) — это не TODO, а защита от расхождения с существующим кодом.
- **Согласованность типов:** `FragmentSplicer.Result` (`.replaced/.notFound/.ambiguous`) одинаков в Task 4 и используется в Task 6. `FragmentEditor.run(...)` сигнатура совпадает в тестах (Task 6 Step 1) и реализации (Step 3). `FragmentPromptBuilder().build(roleContext:instruction:fragment:)` совпадает в Task 5 и Task 6. `SkillPreset(name:prompt:roleKey:order:)` совпадает в Task 2, 6 (контейнер), 9. `StageExecutor.StreamProvider` переиспользуется как тип в Task 6.
