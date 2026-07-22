# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: implementation

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Зафиксировать в git-репозитории (и запушить на GitHub) текущее состояние
промтов этапов, ИИ-ролей и редполитики так, как они сейчас отредактированы
пользователем в приложении. Эти данные живут только в локальной SwiftData базе
(`~/Library/.../com.zykovsrg.SEOContentCreator/.../default.store`), а не в коде,
поэтому нужен экспорт-снимок (JSON) в репозиторий + коммит + push.

## Use Superpowers

no

## Relevant files

- SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift
- SEOContentCreator/SEOContentCreator/Models/ContextBlock.swift
- SEOContentCreator/SEOContentCreator/Models/AIRole.swift
- новая папка со снимком (например docs/prompts-snapshot/)

## Done criteria

- В репозитории появился читаемый файл(ы) со всеми StageTemplate, ContextBlock
  и AIRole записями из текущей SwiftData базы пользователя.
- Изменения закоммичены и запушены в GitHub (после подтверждения пользователя).

## Agent handoff

Last agent: Claude Code

What changed:
Task recorded via task-intake (was empty).

Open risks:
Snapshot is a point-in-time export, not a live sync with the app's SwiftData
store — future edits in the app won't auto-update the repo file.

Next agent should check:
Whether user wants this snapshot process repeated/automated later, or kept as
one-off.
