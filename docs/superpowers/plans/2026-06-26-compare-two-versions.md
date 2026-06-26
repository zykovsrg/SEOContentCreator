# Сравнение двух версий из ленты — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать редактору выбрать две произвольные версии темы в ленте и увидеть их различия в двухстолбцовом read-only окне.

**Architecture:** Чистый UI + переиспользование `ParagraphDiff`. Никаких изменений схемы SwiftData, новых сущностей и зависимостей. Режим выбора живёт внутри `VersionLaneView`; результат показывается в новом `VersionCompareView` (sheet-on-sheet). Логика лимита выбора и разнесения diff по столбцам вынесены в чистые функции и покрыты unit-тестами.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`).

**Build/test note:** CLI `xcodebuild test` зависает в этом окружении (см. память проекта). Для компиляции использовать `xcodebuild build-for-testing`; прогон тестов — в Xcode (Cmd+U). Xcode 16 file-system-sync: новые файлы попадают в таргет автоматически.

---

### Task 1: Хелпер левого столбца в `ParagraphDiff`

Правый столбец (unchanged + added) уже существует как `ParagraphDiff.newSide`. Добавляем симметричный левый столбец (unchanged + removed). DRY: не дублируем алгоритм, фильтруем результат `diff`.

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ParagraphDiff.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ParagraphDiffTests.swift`

- [ ] **Step 1: Написать падающий тест**

Добавить в `struct ParagraphDiffTests` (`ParagraphDiffTests.swift`):

```swift
    @Test func oldSideHelperReturnsOnlyOldSide() {
        let old = "A\n\nB"
        let new = "A\n\nC"
        let left = ParagraphDiff.oldSide(old: old, new: new)
        #expect(left.contains { $0.kind == .removed && $0.text == "B" })
        #expect(left.contains { $0.kind == .unchanged && $0.text == "A" })
        #expect(left.allSatisfy { $0.kind != .added })
    }

    @Test func oldSideIdenticalTextsAllUnchanged() {
        let left = ParagraphDiff.oldSide(old: "A\n\nB", new: "A\n\nB")
        #expect(left.count == 2)
        #expect(left.allSatisfy { $0.kind == .unchanged })
    }
```

- [ ] **Step 2: Запустить тест — убедиться, что не компилируется/падает**

Run: `xcodebuild build-for-testing -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS'`
Expected: FAIL — `oldSide` не найден.

- [ ] **Step 3: Реализовать `oldSide`**

В `enum ParagraphDiff`, сразу после `newSide(old:new:)` (`ParagraphDiff.swift:48`), добавить:

```swift
    /// Left-column view: only `.unchanged` and `.removed` lines (the old version).
    static func oldSide(old: String, new: String) -> [ParagraphDiffLine] {
        diff(old: old, new: new).filter { $0.kind != .added }
    }
```

- [ ] **Step 4: Прогнать тесты в Xcode (Cmd+U) — убедиться, что зелёные**

Expected: `oldSideHelperReturnsOnlyOldSide` и `oldSideIdenticalTextsAllUnchanged` проходят; существующие тесты `ParagraphDiffTests` не сломаны.

- [ ] **Step 5: Коммит**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ParagraphDiff.swift SEOContentCreator/SEOContentCreatorTests/ParagraphDiffTests.swift
git commit -m "feat(diff): add ParagraphDiff.oldSide for left compare column"
```

---

### Task 2: Чистая функция лимита выбора (FIFO, максимум 2)

Логику «отметить/снять, не более двух, при третьей вытеснить самую раннюю» выносим в свободную функцию, чтобы покрыть тестом без UI.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/VersionCompareSelection.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/VersionCompareSelectionTests.swift`

- [ ] **Step 1: Написать падающий тест**

Создать `VersionCompareSelectionTests.swift`:

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct VersionCompareSelectionTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func appendsWhenUnderLimit() {
        let r = compareSelectionToggle(current: [a], tapped: b)
        #expect(r == [a, b])
    }

    @Test func togglingSelectedRemovesIt() {
        let r = compareSelectionToggle(current: [a, b], tapped: a)
        #expect(r == [b])
    }

    @Test func thirdSelectionEvictsEarliest() {
        let r = compareSelectionToggle(current: [a, b], tapped: c)
        #expect(r == [b, c])
    }
}
```

- [ ] **Step 2: Запустить — убедиться, что не компилируется**

Run: `xcodebuild build-for-testing -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS'`
Expected: FAIL — `compareSelectionToggle` не найден.

- [ ] **Step 3: Реализовать функцию**

Создать `VersionCompareSelection.swift`:

```swift
import Foundation

/// Toggles `tapped` in the compare selection, keeping at most two entries.
/// If already selected, it is removed. Otherwise appended; when this would
/// exceed two, the earliest selection is evicted (FIFO).
func compareSelectionToggle(current: [UUID], tapped: UUID) -> [UUID] {
    if let idx = current.firstIndex(of: tapped) {
        var next = current
        next.remove(at: idx)
        return next
    }
    var next = current + [tapped]
    if next.count > 2 { next.removeFirst() }
    return next
}
```

- [ ] **Step 4: Прогнать тесты в Xcode (Cmd+U)**

Expected: все три теста `VersionCompareSelectionTests` зелёные.

- [ ] **Step 5: Коммит**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/VersionCompareSelection.swift SEOContentCreator/SEOContentCreatorTests/VersionCompareSelectionTests.swift
git commit -m "feat(versions): add compareSelectionToggle FIFO selection helper"
```

---

### Task 3: Окно сравнения `VersionCompareView`

Двухстолбцовый read-only diff пары версий. Старшая по `createdAt` — слева (A), младшая — справа (B). Не пишет в `modelContext`.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/VersionCompareView.swift`

- [ ] **Step 1: Создать `VersionCompareView.swift`**

```swift
import SwiftUI

struct VersionCompareView: View {
    @Environment(\.dismiss) private var dismiss
    let versionA: ArticleVersion
    let versionB: ArticleVersion

    /// Older version goes left, newer goes right, regardless of pick order.
    private var older: ArticleVersion {
        versionA.createdAt <= versionB.createdAt ? versionA : versionB
    }
    private var newer: ArticleVersion {
        versionA.createdAt <= versionB.createdAt ? versionB : versionA
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                column(version: older, lines: ParagraphDiff.oldSide(old: older.text, new: newer.text))
                Divider()
                column(version: newer, lines: ParagraphDiff.newSide(old: older.text, new: newer.text))
            }
            Divider()
            HStack { Spacer(); Button("Закрыть") { dismiss() }.keyboardShortcut(.defaultAction) }
                .padding(8)
        }
        .frame(width: 760, height: 560)
    }

    private func column(version: ArticleVersion, lines: [ParagraphDiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.stageTitle).font(.subheadline).bold()
                Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .textSelection(.enabled)
                            .strikethrough(line.kind == .removed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(background(for: line.kind))
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func background(for kind: ParagraphDiffKind) -> Color {
        switch kind {
        case .added:   return Color.green.opacity(0.18)
        case .removed: return Color.red.opacity(0.14)
        case .unchanged: return .clear
        }
    }
}
```

- [ ] **Step 2: Скомпилировать**

Run: `xcodebuild build-for-testing -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add SEOContentCreator/SEOContentCreator/Views/VersionCompareView.swift
git commit -m "feat(versions): add read-only VersionCompareView two-column diff"
```

---

### Task 4: Режим выбора в `VersionLaneView`

Кнопка «Сравнить» включает режим выбора с чекбоксами; «Сравнить выбранные (2)» открывает `VersionCompareView`. Поведение вне режима — без изменений.

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift`

- [ ] **Step 1: Добавить состояние выбора**

После `@State private var groupByStage = false` (`VersionLaneView.swift:10`) добавить:

```swift
    @State private var selecting = false
    @State private var selection: [UUID] = []
    @State private var comparePair: ComparePair?

    private struct ComparePair: Identifiable {
        let id = UUID()
        let a: ArticleVersion
        let b: ArticleVersion
    }
```

- [ ] **Step 2: Добавить тулбар-кнопку режима и кнопку запуска сравнения**

Заменить блок `body` (`VersionLaneView.swift:16-37`) на:

```swift
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Вид", selection: $groupByStage) {
                    Text("По времени").tag(false)
                    Text("По этапам").tag(true)
                }.pickerStyle(.segmented)
                .disabled(selecting)

                if selecting {
                    Button("Отмена") { selecting = false; selection = [] }
                } else {
                    Button("Сравнить") { selecting = true }
                }
            }

            List {
                if groupByStage {
                    ForEach(stageGroups, id: \.0) { stage, items in
                        Section(stage) { ForEach(items) { row($0) } }
                    }
                } else {
                    ForEach(versions) { row($0) }
                }
            }

            HStack {
                if selecting {
                    Button("Сравнить выбранные (\(selection.count))") { startCompare() }
                        .disabled(selection.count != 2)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
            }
        }
        .padding()
        .frame(width: 520, height: 520)
        .sheet(item: $comparePair) { pair in
            VersionCompareView(versionA: pair.a, versionB: pair.b)
        }
    }

    private func startCompare() {
        guard selection.count == 2,
              let a = versions.first(where: { $0.uuid == selection[0] }),
              let b = versions.first(where: { $0.uuid == selection[1] }) else { return }
        comparePair = ComparePair(a: a, b: b)
    }
```

- [ ] **Step 3: Обновить `row` — чекбокс в режиме выбора**

Заменить `private func row(_ v: ArticleVersion)` (`VersionLaneView.swift:45-60`) на:

```swift
    private func row(_ v: ArticleVersion) -> some View {
        HStack {
            if selecting {
                // Tap is handled by the row-level gesture below — no separate
                // gesture here, otherwise a tap on the box toggles twice.
                Image(systemName: selection.contains(v.uuid) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selection.contains(v.uuid) ? Color.accentColor : .secondary)
            }
            VStack(alignment: .leading) {
                Text(v.stageTitle).font(.subheadline)
                Text("\(v.source.title) · \(v.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if topic.currentVersionID == v.uuid {
                Label("Текущая", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).labelStyle(.iconOnly)
            }
            if !selecting {
                Button("Сравнить") { onCompare(v); dismiss() }
                Button("Сделать текущей") { makeCurrent(v) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting { selection = compareSelectionToggle(current: selection, tapped: v.uuid) }
        }
    }
```

- [ ] **Step 4: Скомпилировать**

Run: `xcodebuild build-for-testing -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Ручная проверка (Xcode Run)**

1. Открыть тему с ≥3 версиями → «Версии».
2. Нажать «Сравнить» → у строк появились чекбоксы, поточечные кнопки скрылись.
3. Отметить две версии → кнопка «Сравнить выбранные (2)» активна.
4. Отметить третью → самая ранняя отметка снялась (осталось 2).
5. «Сравнить выбранные» → открылось окно: слева старшая версия (удалённое красным, зачёркнуто), справа младшая (добавленное зелёным).
6. «Закрыть» → вернулись в ленту. «Отмена» → режим выбора выключился, отметки сброшены.

- [ ] **Step 6: Коммит**

```bash
git add SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift
git commit -m "feat(versions): add two-version selection mode to VersionLaneView"
```

---

## Self-review notes

- **Spec coverage:** режим выбора двух версий (Task 4) ✓; новое окно `VersionCompareView` (Task 3) ✓; переиспользование `ParagraphDiff` (Task 1, `oldSide` + существующий `newSide`) ✓; только просмотр, без отката ✓; нет изменений схемы ✓.
- **Спека упоминала `leftSide/rightSide`** — реализовано как `oldSide` (новый) + `newSide` (существующий, не трогаем, чтобы не ломать `SideBySideView`). Семантика та же.
- **Тесты:** `oldSide` (Task 1), FIFO-лимит выбора (Task 2). UI-поведение — ручная проверка (CLI test зависает).
- **Типы согласованы:** `compareSelectionToggle(current:tapped:)`, `ParagraphDiff.oldSide(old:new:)`, `VersionCompareView(versionA:versionB:)`, `ParagraphDiffKind` — единообразны во всех тасках.
