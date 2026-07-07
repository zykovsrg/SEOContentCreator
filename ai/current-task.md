# Current Task

Status: review

Allowed statuses: empty / active / review / blocked / done / paused

Stage: review

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Full UI redesign: persistent sidebar (NavigationSplitView) instead of the
segmented picker, a right-hand native inspector (Замечания / Версии / Семантика /
Лог) instead of stacked modal sheets in the topic workspace, a vertical stage
checklist (StageRailView), and colored status pills + stage-progress dots in the
content plan, plus a category selector for Templates. No data-model or
generation changes.

## Use Superpowers

yes — brainstorming → spec → writing-plans done; executing via TDD for pure
logic + build/manual checks for SwiftUI views.

## Relevant files

- Spec: docs/superpowers/specs/2026-07-07-ui-redesign-design.md
- Plan: docs/superpowers/plans/2026-07-07-ui-redesign.md
- Views/RootView.swift, Views/AppSection.swift
- Views/ContentPlanView.swift, Views/TopicWorkspaceView.swift
- Views/StageBarView.swift → StageRailView.swift, Views/TemplatesView.swift
- Views/DesignSystem.swift (new)
- Logic/TopicStatusStyle.swift, StagePipeline.swift, TemplateChipText.swift,
  TemplateCategory.swift (new)

## Done criteria

- All 10 plan tasks complete; project compiles (build-for-testing).
- New logic covered by Swift Testing tests; Cmd+U green (user-run).
- Manual UI checklist passes in light + dark themes (sidebar, inspector tabs,
  stage rail, status pills, templates categories; all accept/reject/redo paths).

## Agent handoff

Branch: redesign/ui-overhaul (off main commit 82d2fee). All 10 plan tasks
implemented; `build-for-testing` green. Commits bd5f1ec..5f1f598.

Deviations from plan worth noting:
- DesignSystem.swift was first written to the wrong path (outside the target
  source root) and relocated in commit 61fd0eb — now compiles into the app.
- Templates: the editor dictionary ("Словарь правок") was missing from all 6
  categories in the original plan (a gap); it is now reachable under the
  "Редполитика" category and via search. Product blocks are reachable via
  search + the "Добавить" menu only (deliberate per plan; flag for user).
- TemplatesView + TopicWorkspaceView were decomposed into computed subviews and
  TemplatesView's nine .onChange(of: .map(\.uuid)) collapsed into one
  counter-keyed onChange — required to keep the SwiftUI type-checker within
  budget (macOS 26 project hits hard type-check timeouts otherwise).
- Task 9 (workspace inspector) was implemented by the controller directly, not a
  subagent, due to a mid-run subagent API failure + the fragility of the
  brace-level refactor.

Open risks / next steps:
- Cmd+U not run (CLI xcodebuild test hangs — project memory). User must run the
  new tests (TopicStatusStyleTests, StagePipelineTests, TemplateChipTextTests)
  plus the existing suite in Xcode.
- Manual UI checklist (Cmd+R, light + dark) pending — see below in chat.
- After sign-off: task-finish (changelog + optional push of branch + PR).
