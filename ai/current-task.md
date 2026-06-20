# Current Task

Status: active

## Mode

implementation

## Goal

Под-проект «Публикация в Google Docs» — финальный этап пайплайна: публикация принятой версии статьи в Google Docs (односторонне, свой OAuth, Docs/Drive REST API).

## Scope

- Спека: `docs/superpowers/specs/2026-06-21-publishing-design.md`
- План: `docs/superpowers/plans/2026-06-21-publishing.md` (10 задач, TDD)
- Свой OAuth (URLSession + PKCE, без зависимостей), скоупы documents + drive.file.
- markdown→Docs (заголовки/абзацы/жирный/списки, без изображений).
- Модель `ExternalDocument`, повторная публикация новый/перезапись, ключи Google в Keychain.
- Реализуем здесь, через Superpowers (executing-plans / subagent-driven-development).

## Done criteria

- Все задачи плана выполнены, тесты зелёные (Cmd+U).
- Ручные проверки реального OAuth/публикации пройдены (Task 10).
- changelog обновлён.

## Notes

- Публикация реализуется как кнопка в тулбаре + sheet, НЕ как case в `PipelineStage` (он для ИИ-этапов).
- В коде уже были заготовки: `Topic.externalDocURL`/`publishedAt`, статус `published`, `VersionSource.importFromDocs`.
