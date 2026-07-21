# Header navigation — design

Date: 2026-07-21

## Problem

The four main sections live in a `NavigationSplitView` sidebar. The sidebar eats
~220 px of width that the content plan table and the knowledge tree could use, and
the existing shortcuts are inconsistent (Cmd+2 opens Шаблоны, Быстрая проверка has
no shortcut at all).

## Decision

Replace the sidebar with a section switcher in the window toolbar.

- The window becomes single-column: `RootView` renders only the selected section.
- The switcher is a `ToolbarItem` at `.navigation` placement, so macOS supplies the
  translucent, blurred toolbar background and handles the traffic-light inset.
- Each item is icon + label; the selected one gets a `Color.brandAccent` capsule.
- A thin divider sits between `quickCheck` and `templates`, replacing the old
  "Работа" / "Знания" group headings.
- A gear `ToolbarItem` at `.primaryAction` sends `showSettingsWindow:`, same as the
  old sidebar footer button.
- Sections keep their own `.toolbar` content (e.g. ContentPlanView's "Открыть"),
  which merges into the same toolbar to the right of the switcher.

## Shortcuts

`Cmd+1` Контент-план, `Cmd+2` Быстрая проверка, `Cmd+3` Шаблоны, `Cmd+4` База знаний
— matching the visual order. The number → section mapping is a pure function
(`AppSection.shortcutKey` / `AppSection(shortcutIndex:)`) so it can be unit tested
without instantiating any view.

## Alternatives considered

- **Custom header with `.windowStyle(.hiddenTitleBar)`**: more design freedom, but
  we would have to hand-manage the traffic-light inset and relocate every section's
  existing toolbar button. Rejected as more risk for a cosmetic gain.
- **Toolbar plus a collapsible sidebar**: keeps both navigation surfaces. Rejected
  as visually redundant.
- **Bare 1–4 keys**: would fire while the user types in the editor. Rejected.

## Risks

- Toolbar crowding if a section later adds many buttons. Accepted for now.
- No data, storage, or pipeline logic is touched.

## Verification

- Unit test for the shortcut mapping.
- Build the app and visually check all four sections plus the gear button.
