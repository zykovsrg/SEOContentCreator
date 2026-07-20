# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: intake

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Two related publishing-pipeline features: (1) article illustrations must be automatically uploaded to a specific Google Drive folder (https://drive.google.com/drive/folders/1XXEa9SH51qKIbUUHrZNDfdsrXDZ3LPlB); (2) after the "Финальная вычитка" stage, an H2 section «Техническая информация» must be appended to the end of the document with a fixed template: Тайтл, Дескрипшн, Эксперт ([врач_данные]), Врачи отделения (manual), Направления, Раздел, Иллюстрации (link to the Drive folder).

## Use Superpowers

yes

## Relevant files

unknown (likely: ArticlePublisher, ImageGenerator, GoogleAuthService, PipelineStage, Topic model)

## Done criteria

- Generated article illustrations are uploaded to the specified Google Drive folder automatically.
- After final review, the article ends with an H2 «Техническая информация» section following the agreed template.
- Fields with no data source (e.g. «Врачи отделения») stay as manual placeholders.

## Agent handoff

Last agent: Claude Code

What changed:
Task recorded through task-intake; requirements clarification (Superpowers brainstorming) starting.

Open risks:
Google Drive upload likely needs a new OAuth scope (drive.file) — re-auth may be required; template fields need mapping to existing Topic/model data.

Next agent should check:
GoogleAuthService scopes, how images are stored after generation, where «Финальная вычитка» output is finalized.

