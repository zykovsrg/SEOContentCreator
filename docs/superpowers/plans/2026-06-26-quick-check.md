# Режим «Быстрая проверка» Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Лист «Быстрая проверка» — разовая проверка вставленного текста одним checking-этапом без создания темы, с принятием/отклонением замечаний, копированием и сохранением как тему.

**Architecture:** Подход A из спеки. Новый метод `StageExecutor.executeQuickCheck` гоняет один checking-этап на произвольном тексте без персистентности (без `GenerationJob`/`ArticleVersion`/`Topic`), собирая промт существующим `PromptBuilder` через транзитный несохранённый `Topic`. UI — новый `QuickCheckSheet`, переиспользует `RemarksPanelView` и `RemarkApplier`. Точка входа — кнопка в тулбаре `ContentPlanView`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`), macOS. Тесты компилируются через `xcodebuild build-for-testing`, запускаются в Xcode (Cmd+U) — CLI `xcodebuild test` зависает.

Spec: `docs/superpowers/specs/2026-06-26-quick-check-design.md`

---

## File Structure

- `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift` — **modify**: добавить метод `executeQuickCheck`.
- `SEOContentCreator/SEOContentCreator/Logic/QuickCheckTitle.swift` — **create**: чистый хелпер подсказки имени темы.
- `SEOContentCreator/SEOContentCreator/Views/QuickCheckSheet.swift` — **create**: сам лист.
- `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift` — **modify**: кнопка тулбара + `.sheet`.
- `SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift` — **create**: тесты `executeQuickCheck` и `QuickCheckTitle`.

Переиспользуется без изменений: `PromptBuilder`, `RemarksParser`, `RemarkApplier`, `RemarksPanelView`, `Remark`, `StageTemplate`, `Topic`, `ArticleVersion`.

---

## Task 1: `executeQuickCheck` на StageExecutor

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift`

- [ ] **Step 1: Написать падающий тест**

Создать файл `SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import SEOContentCreator

@MainActor
struct QuickCheckExecutorTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AIRole.self, ContextBlock.self, GenerationJob.self, ArticleVersion.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func tokenStream(_ text: String) -> StageExecutor.StreamProvider {
        { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.token(text))
                continuation.yield(.finish(reason: "stop"))
                continuation.finish()
            }
        }
    }

    private let remarkJSON = """
    {"remarks":[{"category":"SEO","quote":"плохо","suggestion":"хорошо","explanation":"так лучше"}]}
    """

    @Test func parsesRemarksFromResponse() async throws {
        let context = try makeContext()
        let executor = StageExecutor(streamProvider: tokenStream(remarkJSON), keyProvider: { "key" })
        let template = StageTemplate(stage: .seoCheck, systemPrompt: "sys", userPromptTemplate: "Проверь: {{текущий_текст}}")

        await executor.executeQuickCheck(stage: .seoCheck, pastedText: "плохо текст", template: template, in: context)

        #expect(executor.remarks.count == 1)
        #expect(executor.remarks.first?.suggestion == "хорошо")
        #expect(executor.lastErrorMessage == nil)
    }

    @Test func doesNotPersistJobOrVersion() async throws {
        let context = try makeContext()
        let executor = StageExecutor(streamProvider: tokenStream(remarkJSON), keyProvider: { "key" })
        let template = StageTemplate(stage: .factCheck, systemPrompt: "sys", userPromptTemplate: "{{текущий_текст}}")

        await executor.executeQuickCheck(stage: .factCheck, pastedText: "текст", template: template, in: context)

        let jobs = try context.fetch(FetchDescriptor<GenerationJob>())
        let versions = try context.fetch(FetchDescriptor<ArticleVersion>())
        #expect(jobs.isEmpty)
        #expect(versions.isEmpty)
    }
}
```

- [ ] **Step 2: Проверить, что тест НЕ компилируется/падает**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: ошибка компиляции — `value of type 'StageExecutor' has no member 'executeQuickCheck'`.

- [ ] **Step 3: Реализовать метод**

В `StageExecutor.swift` добавить метод внутри класса (после `execute(...)`, перед `private func fetchRole`):

```swift
    /// Runs a single checking stage on arbitrary pasted text, without persisting
    /// anything (no GenerationJob, no ArticleVersion, no Topic). Fills `remarks`.
    /// Intended for the topic-less "Быстрая проверка" sheet.
    func executeQuickCheck(
        stage: PipelineStage,
        pastedText: String,
        template: StageTemplate,
        in context: ModelContext
    ) async {
        isRunning = true
        streamingText = ""
        lastErrorMessage = nil
        lastWarningMessage = nil
        remarks = []

        let role = fetchRole(for: stage, in: context)
        do {
            let key = try keyProvider()
            let roleContext = buildRoleContext(for: role, in: context)
            // Transient, NOT inserted into the context: only carries the pasted text.
            let scratch = Topic(title: "", articleType: .info)
            let prompt = PromptBuilder().build(
                template: template, topic: scratch,
                currentText: pastedText, selectedBlocks: [],
                roleContext: roleContext
            )
            var collected = ""
            var truncated = false
            for try await event in streamProvider(
                key, prompt.system, prompt.user,
                template.modelName, template.temperature, template.maxTokens,
                template.reasoningEffort
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
            remarks = RemarksParser.parse(rawText: collected)
        } catch {
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            lastErrorMessage = message
        }

        isRunning = false
    }
```

- [ ] **Step 4: Проверить, что тесты компилируются (и пройдут в Cmd+U)**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`, без `error:`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift
git commit -m "feat(quick-check): topic-less executeQuickCheck on StageExecutor"
```

---

## Task 2: Хелпер подсказки имени темы

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/QuickCheckTitle.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift` (дополнить)

- [ ] **Step 1: Дописать падающий тест**

В конец `QuickCheckTests.swift` добавить:

```swift
struct QuickCheckTitleTests {
    @Test func usesFirstNonEmptyLine() {
        #expect(QuickCheckTitle.suggest(from: "\n  \nЗаголовок статьи\nостальное") == "Заголовок статьи")
    }

    @Test func trimsAndCapsLength() {
        let long = String(repeating: "а", count: 200)
        #expect(QuickCheckTitle.suggest(from: long).count == 80)
    }

    @Test func fallbackForEmptyText() {
        #expect(QuickCheckTitle.suggest(from: "   \n  ") == "Быстрая проверка")
    }
}
```

- [ ] **Step 2: Проверить, что тест НЕ компилируется**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: ошибка — `cannot find 'QuickCheckTitle' in scope`.

- [ ] **Step 3: Реализовать хелпер**

Создать `SEOContentCreator/SEOContentCreator/Logic/QuickCheckTitle.swift`:

```swift
import Foundation

/// Suggests a topic title from pasted text: first non-empty line, trimmed and
/// capped at 80 characters. Falls back to a fixed label when the text is blank.
enum QuickCheckTitle {
    static func suggest(from text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        }
        return "Быстрая проверка"
    }
}
```

- [ ] **Step 4: Проверить компиляцию**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/QuickCheckTitle.swift SEOContentCreator/SEOContentCreatorTests/QuickCheckTests.swift
git commit -m "feat(quick-check): title suggestion helper"
```

---

## Task 3: Лист `QuickCheckSheet`

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/QuickCheckSheet.swift`

UI-задача, юнит-тестов нет (проверка вручную в Task 5). Логика разбора уже покрыта Task 1–2.

- [ ] **Step 1: Создать вью**

Создать `SEOContentCreator/SEOContentCreator/Views/QuickCheckSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct QuickCheckSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Только проверки (kind == .checking).
    private let checkStages: [PipelineStage] = [.seoCheck, .factCheck, .finalReview]

    @State private var inputText = ""
    @State private var selectedStage: PipelineStage = .seoCheck
    @State private var executor: StageExecutor?
    @State private var acceptedRemarkIDs: Set<UUID> = []
    @State private var rejectedRemarkIDs: Set<UUID> = []
    @State private var didRun = false

    // Сохранение как тему.
    @State private var showingSaveDialog = false
    @State private var newTopicTitle = ""
    @State private var copiedNote = false

    private var remarks: [Remark] { executor?.remarks ?? [] }
    private var isRunning: Bool { executor?.isRunning ?? false }

    private var correctedText: String {
        let accepted = remarks.filter { acceptedRemarkIDs.contains($0.id) }
        return RemarkApplier.apply(base: inputText, accepted: accepted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Быстрая проверка").font(.title2).bold()
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            Picker("Проверка", selection: $selectedStage) {
                ForEach(checkStages) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Вставьте текст для проверки").font(.headline)
            TextEditor(text: $inputText).frame(minHeight: 140).border(.gray.opacity(0.3))

            HStack {
                Button("Проверить") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                if isRunning { ProgressView().controlSize(.small) }
                if let msg = executor?.lastErrorMessage {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            if didRun && !isRunning {
                Divider()
                RemarksPanelView(
                    remarks: remarks,
                    acceptedIDs: acceptedRemarkIDs,
                    rejectedIDs: rejectedRemarkIDs,
                    onAccept: { acceptedRemarkIDs.insert($0.id); rejectedRemarkIDs.remove($0.id) },
                    onReject: { rejectedRemarkIDs.insert($0.id); acceptedRemarkIDs.remove($0.id) },
                    onSelect: { _ in }
                )
                .frame(minHeight: 160)

                HStack {
                    Button("Скопировать результат") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(correctedText, forType: .string)
                        copiedNote = true
                    }
                    Button("Сохранить как тему") {
                        newTopicTitle = QuickCheckTitle.suggest(from: correctedText)
                        showingSaveDialog = true
                    }
                    Spacer()
                    if copiedNote { Text("Скопировано").font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
        .alert("Сохранить как тему", isPresented: $showingSaveDialog) {
            TextField("Название темы", text: $newTopicTitle)
            Button("Сохранить") { saveAsTopic() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Будет создана новая тема с исправленным текстом.")
        }
    }

    private func run() {
        copiedNote = false
        acceptedRemarkIDs = []
        rejectedRemarkIDs = []
        let template = fetchTemplate(for: selectedStage)
        let exec = StageExecutor.live(model: template.modelName)
        executor = exec
        didRun = true
        Task {
            await exec.executeQuickCheck(stage: selectedStage, pastedText: inputText, template: template, in: context)
        }
    }

    private func saveAsTopic() {
        let title = newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = Topic(title: title.isEmpty ? "Быстрая проверка" : title, articleType: .info)
        context.insert(topic)
        let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: correctedText)
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        dismiss()
    }

    private func fetchTemplate(for stage: PipelineStage) -> StageTemplate {
        let raw = stage.rawValue
        let descriptor = FetchDescriptor<StageTemplate>(predicate: #Predicate { $0.stageRaw == raw })
        if let found = (try? context.fetch(descriptor))?.first { return found }
        StageTemplateSeeder.seedIfNeeded(in: context)
        return (try? context.fetch(descriptor))?.first
            ?? StageTemplate(stage: stage, systemPrompt: "", userPromptTemplate: "{{текущий_текст}}")
    }
}
```

- [ ] **Step 2: Проверить компиляцию**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/QuickCheckSheet.swift
git commit -m "feat(quick-check): QuickCheckSheet view"
```

---

## Task 4: Точка входа в `ContentPlanView`

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`

- [ ] **Step 1: Добавить state-флаг**

Рядом с `@State private var showingBrief = false` (строка ~10) добавить:

```swift
    @State private var showingQuickCheck = false
```

- [ ] **Step 2: Добавить кнопку в тулбар**

В блоке `.toolbar { ... }` перед `ToolbarItem { Button { showingBrief = true } ... }` (строка ~54) вставить:

```swift
            ToolbarItem {
                Button { showingQuickCheck = true } label: {
                    Label("Быстрая проверка", systemImage: "checkmark.circle")
                }
            }
```

- [ ] **Step 3: Добавить sheet**

После `.sheet(item: $editingTopic) { BriefView(topic: $0) }` (строка ~60) добавить:

```swift
        .sheet(isPresented: $showingQuickCheck) { QuickCheckSheet() }
```

- [ ] **Step 4: Проверить компиляцию**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift
git commit -m "feat(quick-check): entry point in content plan toolbar"
```

---

## Task 5: Финальная проверка

**Files:** нет правок кода (только прогон).

- [ ] **Step 1: Полная компиляция приложения и тестов**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | grep -E "error:|TEST BUILD"`
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 2: Тесты в Xcode (пользователь)**

Cmd+U. Expected: `QuickCheckExecutorTests` (2) и `QuickCheckTitleTests` (3) зелёные, остальной набор не сломан.

- [ ] **Step 3: Ручная проверка UI (пользователь, Cmd+R)**

  - На «Контент-план» в тулбаре есть кнопка «Быстрая проверка»; открывает лист.
  - Вставить текст, выбрать проверку, «Проверить» → появляются замечания.
  - Принять часть → «Скопировать результат» кладёт исправленный текст в буфер.
  - «Сохранить как тему» → поле имени (предзаполнено), сохранение создаёт новую тему с исправленным текстом; в обычной ленте версий она открывается.
  - До «Сохранить как тему» новых тем в списке не появляется.

- [ ] **Step 4: task-finish**

Предложить `task-finish` (changelog + закрытие FT-20260623-004, merge feature/quick-check в main по подтверждению).

---

## Self-Review

**Spec coverage:**
- Лист с экрана списка тем → Task 3 + Task 4. ✅
- Одна из трёх проверок (Picker) → Task 3 (`checkStages`). ✅
- Запуск тем же StageExecutor без темы → Task 1 (`executeQuickCheck`). ✅
- Замечания + принять/отклонить + исправленный текст → Task 3 (`RemarksPanelView` + `RemarkApplier`). ✅
- «Скопировать результат» / «Сохранить как тему» (исправленный текст, имя вводит пользователь) → Task 3 (`saveAsTopic`, alert с `TextField`, `QuickCheckTitle`). ✅
- Ничего не сохраняется автоматически → Task 1 (нет персистентности), Task 3 (Topic создаётся только в `saveAsTopic`). Проверка — Task 1 `doesNotPersistJobOrVersion`, Task 5 Step 3. ✅
- Без изменений схемы SwiftData → новых `@Model`/полей нет. ✅
- Обработка ошибок (нет ключа, обрыв по токенам, пустой ввод, пустой JSON) → Task 1 (catch + `lastWarningMessage`), Task 3 (disabled при пустом вводе), `RemarksParser` отдаёт [] + `RemarksPanelView` «Замечаний нет». ✅

**Placeholder scan:** плейсхолдеров нет — весь код приведён.

**Type consistency:** `executeQuickCheck(stage:pastedText:template:in:)`, `QuickCheckTitle.suggest(from:)`, `RemarksPanelView(remarks:acceptedIDs:rejectedIDs:onAccept:onReject:onSelect:)`, `RemarkApplier.apply(base:accepted:)`, `ArticleVersion(stage:source:text:)`, `Topic(title:articleType:)`, `StageTemplate(stage:systemPrompt:userPromptTemplate:)`, `StageExecutor.live(model:)` — сверено с текущим кодом.
