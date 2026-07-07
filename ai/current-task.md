# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: implementation

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

Branch: redesign/ui-overhaul (off main commit 82d2fee). Spec + plan committed.
Next: execute plan Task 1 onward.
