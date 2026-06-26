# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: spec

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

FT-20260623-004 — Режим «Быстрая проверка». Отдельный лист для разовой проверки
произвольного текста без создания темы: вставить текст, выбрать одну из трёх проверок
(Проверка SEO / Фактчекинг / Финальная вычитка), получить замечания с принять/отклонить
и исправленный текст. Кнопки «Скопировать результат» и «Сохранить как тему».

## Use Superpowers

yes — новая фича, brainstorming → spec → plan. Спека: docs/superpowers/specs/2026-06-26-quick-check-design.md

## Spec

docs/superpowers/specs/2026-06-26-quick-check-design.md (подход A: executeQuickCheck в
StageExecutor + временный Topic для промта; без изменений схемы SwiftData).

## Relevant files

- SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift (новый метод executeQuickCheck)
- SEOContentCreator/SEOContentCreator/Views/QuickCheckSheet.swift (новый)
- SEOContentCreator/SEOContentCreator/Views/RootView.swift или ContentView.swift (точка входа)
- переиспользование: PromptBuilder, RemarksParser, RemarkApplier, RemarksPanelView
- тесты: новый QuickCheckTests

## Done criteria

- Лист открывается с экрана списка тем; работает без создания темы.
- Проверка выдаёт замечания + принять/отклонить + исправленный текст.
- «Скопировать результат» и «Сохранить как тему» (исправленный текст, имя вводит пользователь).
- Автоматически в базу ничего не пишется.
- xcodebuild build-for-testing зелёный; тесты Cmd+U зелёные.

## Agent handoff

Last agent: Claude (Opus 4.8)

What changed: brainstorming завершён, спека написана; ждём ревью пользователя перед writing-plans.

Open risks: транзитный несохранённый Topic в PromptBuilder; executeQuickCheck не должен персистить GenerationJob.

Next agent should check: после ревью спеки — writing-plans, затем реализация подхода A.
