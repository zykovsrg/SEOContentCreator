# Сравнение двух версий из ленты (FT-20260623-005)

Date: 2026-06-26
Status: approved
Source future task: FT-20260623-005

## Goal

Дать редактору выбрать **две произвольные** исторические версии темы из ленты
версий и увидеть их различия side-by-side. Сейчас сравнение доступно только в
двух частных случаях: при принятии результата этапа (новая vs текущая) и
поточечная кнопка «Сравнить» в ленте (историческая vs текущая). Произвольная
пара версий — не поддерживается.

## Scope

In scope:

- Режим выбора двух версий в `VersionLaneView` (чекбоксы + кнопка «Сравнить выбранные»).
- Новое окно `VersionCompareView` — двухстолбцовый diff пары версий, только просмотр.
- Переиспользование `ParagraphDiff` для вычисления различий.

Out of scope:

- Откат/«сделать текущей» из окна сравнения (остаётся в самой ленте).
- Изменения схемы SwiftData (новых сущностей и полей нет).
- Изменение существующего `SideBySideView` и accept/reject-потока этапов.

## Architecture

Только UI + переиспользование существующей чистой логики `ParagraphDiff`.
Никаких изменений модели данных и зависимостей.

### 1. Режим выбора в `VersionLaneView`

- Новое состояние:
  - `@State private var selecting: Bool = false` — включён ли режим выбора.
  - `@State private var selection: [UUID] = []` — отмеченные версии, в порядке отметки.
- В тулбаре окна — кнопка **«Сравнить»**, включающая `selecting`.
- В режиме выбора у каждой строки слева показывается чекбокс; поточечные кнопки
  «Сравнить» / «Сделать текущей» в строке скрываются, чтобы не было визуального шума.
- **Лимит — две версии.** При попытке отметить третью снимается **самая ранняя**
  отметка (FIFO по порядку клика): `selection` ведёт себя как очередь длины 2.
- Внизу — кнопка **«Сравнить выбранные (2)»**, активна только при `selection.count == 2`.
  Нажатие открывает `VersionCompareView` для отмеченной пары.
- Когда `selecting == false`, поведение ленты — как сейчас (поточечная «Сравнить»
  через `onCompare`, «Сделать текущей»).
- Кнопка выхода из режима выбора («Отмена») сбрасывает `selection` и `selecting`.

### 2. Новое окно `VersionCompareView`

- Вход: две `ArticleVersion`.
- Внутри сортирует пару по `createdAt`: **старшая → левый столбец (A),
  младшая → правый (B)** — diff читается «что изменилось со временем»,
  независимо от порядка кликов пользователя.
- Рендер на базе `ParagraphDiff.diff(old: A.text, new: B.text)`:
  - Левый столбец: абзацы `.unchanged` + `.removed`; `.removed` — красным,
    зачёркнутым.
  - Правый столбец: абзацы `.unchanged` + `.added`; `.added` — зелёным фоном.
- Заголовок окна: `«{stageTitle A} ({дата A}) ↔ {stageTitle B} ({дата B})»`.
- **Только просмотр.** Действий нет, кнопка «Закрыть».

### 3. Diff-хелпер

`ParagraphDiff` уже даёт объединённый список `[ParagraphDiffLine]` с видами
`.unchanged/.added/.removed`. Добавляются два тонких хелпера для разнесения по
столбцам (чистые функции, без UI):

- `leftSide(old:new:)` → `[ParagraphDiffLine]` со строками `.unchanged` и `.removed`.
- `rightSide(old:new:)` → `[ParagraphDiffLine]` со строками `.unchanged` и `.added`
  (= уже существующий `newSide`, переименование/алиас на усмотрение плана).

## Data flow

```
VersionLaneView (selecting) --[выбранная пара UUID → ArticleVersion]-->
  VersionCompareView --(ParagraphDiff.diff)--> два столбца (read-only)
```

Окно сравнения не пишет в `modelContext` и не меняет `topic.currentVersionID`.

## Error / edge handling

- Кнопка «Сравнить выбранные» неактивна, пока не выбрано ровно 2 версии.
- Одна и та же версия не может попасть в пару дважды (выбор по уникальному UUID).
- Если у версий идентичный текст — diff покажет все абзацы как `.unchanged`
  (корректное «нет различий»).
- Архивные версии (`isArchived`) в ленте не показываются — поведение наследуется,
  для сравнения они недоступны.

## Testing

- Unit-тесты на хелперы `leftSide`/`rightSide` (`ParagraphDiffTests`):
  - левая сторона не содержит `.added`;
  - правая сторона не содержит `.removed`;
  - идентичные тексты → только `.unchanged` с обеих сторон.
- Логику ограничения выбора (очередь длины 2, FIFO-вытеснение) вынести в
  тестируемую чистую функцию и покрыть unit-тестом: отметка третьей версии
  вытесняет самую раннюю.
- UI-проверка вручную (CLI `xcodebuild test` зависает — компиляция через
  `xcodebuild build-for-testing`, прогон тестов в Xcode Cmd+U).

## Risks

- Низкие: нет миграции, нет внешних зависимостей.
- Главное — не задеть существующий `onCompare`-поток и accept/reject-машину
  в `TopicWorkspaceView`; режим выбора живёт целиком внутри `VersionLaneView`.

## Relevant files

- `SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift` — режим выбора.
- `SEOContentCreator/SEOContentCreator/Views/VersionCompareView.swift` — новое окно (создаётся).
- `SEOContentCreator/SEOContentCreator/Logic/ParagraphDiff.swift` — хелперы столбцов.
- `SEOContentCreator/SEOContentCreatorTests/ParagraphDiffTests.swift` — тесты.
