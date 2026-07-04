# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: planning

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Merge "Ручная правка" (ManualEditSheet) and "Правка фрагмента" (FragmentEditSheet)
into one "Редактор" screen: freely edit the full article text and, without
leaving the screen, select a fragment and regenerate it via a skill preset or a
custom comment, any number of times, before saving once as a single new
ArticleVersion.

## Use Superpowers

yes

## Relevant files

- SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift (new, replaces the two below)
- SEOContentCreator/SEOContentCreator/Views/ManualEditSheet.swift (deleted by plan)
- SEOContentCreator/SEOContentCreator/Views/FragmentEditSheet.swift (deleted by plan)
- SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift (extended)
- SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift (toolbar/sheet wiring)
- SEOContentCreator/SEOContentCreator/Logic/FragmentEditor.swift (simplified)
- SEOContentCreator/SEOContentCreator/Logic/FragmentSplicer.swift (deleted by plan)
- SEOContentCreator/SEOContentCreator/Logic/EditorSessionState.swift (new)

## Done criteria

- Matches design doc `docs/superpowers/specs/2026-07-04-unified-editor-design.md`
  and plan `docs/superpowers/plans/2026-07-04-unified-editor.md`, task by task.
- `xcodebuild build-for-testing` succeeds with zero references to
  ManualEditSheet/FragmentEditSheet/FragmentSplicer remaining.
- New/updated automated tests pass (EditorSessionStateTests, FragmentEditorTests).
- Manual QA checklist (plan Task 7) walked through in the running app.

## Agent handoff

Last agent: Claude (Fable 5)

What changed: brainstormed and approved a design doc, then wrote a full
task-by-task implementation plan (superpowers:writing-plans). No application
code changed yet — design and plan docs only.

Open risks: the floating "Переписать" button's exact on-screen positioning
(computed via NSLayoutManager/NSTextView coordinate conversion in
MarkdownTextEditor, plan Task 4) is the one piece of this plan that can only be
confirmed by actually running the app — flagged in the plan and covered by the
Task 7 manual QA checklist.

Next agent should check: execute the plan at
`docs/superpowers/plans/2026-07-04-unified-editor.md` task by task (user was
about to choose subagent-driven vs. inline execution when this was last
touched — ask if not already decided), then run the manual QA checklist before
proposing task-finish.
