# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: planning

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Let the user mark a commercial section of an article in the "Редактор" screen
with [[БЛОК]]/[[/БЛОК]] markers (Cmd+Shift+K or a toolbar button), and have it
automatically become a bordered 1×1 table when the article is published to
Google Docs.

## Use Superpowers

yes

## Relevant files

- SEOContentCreator/SEOContentCreator/Logic/CommercialBlockSplitter.swift (new)
- SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift (restructured)
- SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift (wired up)
- SEOContentCreator/SEOContentCreator/Views/MarkdownTextEditor.swift (new shortcut/trigger)
- SEOContentCreator/SEOContentCreator/Views/EditorSheet.swift (toolbar button)

## Done criteria

- Matches design doc `docs/superpowers/specs/2026-07-05-commercial-block-markers-design.md`
  and plan `docs/superpowers/plans/2026-07-05-commercial-block-markers.md`, task by task.
- `xcodebuild build-for-testing` succeeds; new/updated automated tests pass.
- Mandatory live Google Docs verification (plan Task 6) confirms a real
  published document shows a correctly bordered table with the right text,
  in both "new document" and "overwrite" publish modes.

## Agent handoff

Last agent: Claude (Fable 5)

What changed: brainstormed and approved a design doc, then wrote a full
task-by-task implementation plan (superpowers:writing-plans). No application
code changed yet — design and plan docs only.

Open risks: the two Google Docs table index constants
(`DocsRequestBuilder.tableCellContentOffset`, `tableClosingOffset`) are
best-documented estimates, not yet verified against a live document — plan
Task 6 requires live verification/correction before this can be trusted.

Next agent should check: execute the plan at
docs/superpowers/plans/2026-07-05-commercial-block-markers.md task by task,
then run the mandatory live Google Docs check in Task 6 before proposing
task-finish.
