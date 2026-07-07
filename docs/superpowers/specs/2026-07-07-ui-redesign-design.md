# UI Redesign — Design Spec

Date: 2026-07-07
Branch: `redesign/ui-overhaul`
Status: approved (design), pending implementation plan

## Goal

Redesign the SEO Content Creator interface to be convenient and logical, using
patterns from modern desktop apps (Linear, Things, Craft): one persistent
sidebar, a right-hand inspector instead of stacked modal sheets, and the stage
pipeline as a vertical checklist. Visual mockup approved by the user.

## Problems being solved

Found by reading the current screen code:

1. **12 modal sheets in the topic workspace** — versions, log, semantics,
   hints, editor, publish, images, product blocks, structure all open over the
   text; article and its context can't be seen at once.
2. **9 equal-weight toolbar buttons** — no visual hierarchy between the primary
   action and reference panels.
3. **Three different navigation models** — segmented picker (RootView),
   full-screen swap with a hand-rolled Back button (topic workspace), and a
   proper split view only in KnowledgeBase.
4. **Topic status is plain text** — no color, no pipeline progress at a glance.
5. **Stage bar is a horizontal capsule strip** — doesn't guide the next step and
   hides when the window is narrow.
6. **Templates is one long list of 8 sections** — only findable by scrolling.

## Non-goals

- No changes to the data model, storage, SwiftData schema, or migrations.
- No changes to generation logic, prompt building, or networking.
- Editor, Publish, Brief, Images, Product blocks, Structure stay as modal
  sheets — they are focused editing tasks that suit a sheet.
- Settings stays a native macOS `Settings` scene (Cmd+,), not a sidebar item.

## Platform

macOS deployment target 26.3 — native `NavigationSplitView` and `.inspector()`
are available and are the intended mechanisms.

## Components

### 1. Navigation shell — `RootView`

Replace the segmented `Picker` with `NavigationSplitView`:

- Sidebar `List(selection:)` with two sections:
  - **Работа**: Контент-план, Быстрая проверка (see note)
  - **Знания**: Шаблоны, База знаний
- Detail column renders the selected section.
- Cmd+1/2/3 keep switching sections; the selected sidebar row shows which is
  active (replaces the invisible shortcut buttons).
- Seeder `.task` block stays as-is.

Note on **Быстрая проверка**: it operates on ad-hoc pasted text via
`QuickCheckSheet`. Selecting a navigation row should not open a modal, so it
stays a button in the Контент-план toolbar, not a sidebar section. (Deviation
from the mockup, accepted by the user.)

### 2. Topic workspace — `TopicWorkspaceView` (highest risk)

- Full-screen swap (`opened` state + hand-rolled Back) → push onto a
  `NavigationStack` inside the split view detail, with the native back button.
- Right-hand **inspector** via native `.inspector()` with a segmented tab
  control: **Замечания / Версии / Семантика / Лог**. The following sheets move
  into inspector tabs: `VersionLaneView`, `JobLogView`, `SemanticsEditorSheet`.
- The current "reviewing remarks" mode (the two-column `isReviewing` branch with
  `RemarksPanelView`) becomes the **Замечания** inspector tab. All
  accept / reject / redo / partial-accept logic is preserved unchanged; only its
  container moves.
- Stays modal: Редактор (`EditorSheet`), Публикация (`PublishSheet`), Бриф,
  Изображения (`ImagesView`), Продуктовые блоки (`ProductBlocksSheet`),
  Структура (`StructureEditorSheet`).
- Bottom action bar: left shows the stage that will run + model + rough token
  estimate; right holds the single primary button "Запустить этап" that becomes
  "Стоп" while running.
- Toolbar shrinks: reference panels move to the inspector, so the toolbar keeps
  only genuinely primary/modal actions (Редактор, Изображения, Опубликовать,
  Рекомендации по промтам, inspector toggle).

### 3. Stage rail — `StageBarView` → `StageRailView`

Horizontal capsules → vertical checklist, top to bottom:

- done (✓ green) / current (● accent) / upcoming (empty circle),
- stage title + AI agent name,
- a header line "N из 8 · дальше: <next stage>".

`StageProgress` completion logic is reused unchanged.

### 4. Content plan — `ContentPlanView`

- Status text → colored `StatusPill` (grey brief / amber in-progress / green
  done). Color derived from `TopicStatus.compute`.
- New "Этапы" column: an 8-dot mini progress view driven by
  `StageProgress.isCompleted` per stage.
- Keep the existing `Table`, search, filters, context menu, delete dialog.

### 5. Templates — `TemplatesView`

- One long `List` of 8 sections → a category selector (tabs / segmented) plus a
  filtered list for the active category.
- Stage-prompt rows show chips: model · token limit · reasoning effort (data
  already on `StageTemplate` / `StageTemplateContent`).
- One "Добавить" menu button replaces the per-section add buttons.
- Search filters across all categories.
- Detail editors (`TemplateEditorView`, `RoleEditorView`, etc.) are reused
  unchanged.

### 6. Design system — new file(s)

A small design-tokens layer plus reusable components:

- Semantic tokens: status colors (good / warning / neutral), spacing scale.
- Components: `StatusPill`, `StageProgressDots`, `Chip`, inspector container.
- Native macOS materials; correct in light and dark themes.

## Testing strategy

TDD for pure, testable logic (new small types / functions):

- status → color/label mapping,
- completed-stage count and "next stage" computation,
- templates category filtering + search,
- inspector tab availability (e.g. Замечания enabled only when remarks exist).

SwiftUI layout and interaction wiring are verified by a manual checklist plus
`xcodebuild build-for-testing`. Full unit run is Cmd+U in Xcode (CLI
`xcodebuild test` hangs — see project memory `xcodebuild-test-runner-hang`).

Manual checklist must cover, in light and dark themes:

- sidebar switching + Cmd+1/2/3, selection highlight,
- opening/closing a topic with the native back button,
- inspector tabs show versions / log / semantics / remarks; remark click
  highlights its quote in the text; accept/reject/redo still work,
- run a stage → pending version → accept/reject/partial still work,
- content-plan status pills and stage-progress column,
- templates category switching, chips, add menu, search.

## Rollout

Single branch `redesign/ui-overhaul`, implemented in dependency order:
design system → navigation shell → content plan → stage rail → templates →
workspace inspector (last, highest risk). Each unit builds green before the
next. No data migration, so rollback is a branch discard.

## Key risk

`TopicWorkspaceView` has a complex conditional body (reviewing / comparing /
single). The inspector refactor must preserve every accept/reject/redo/partial
path. Mitigation: move logic in small steps, keep the existing helper methods
(`acceptAll`, `reject`, `applyPartial`, `finishReview`, `redoRemark`,
`restoreReviewIfNeeded`) intact, and manually verify each path.
