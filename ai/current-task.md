# Current Task

Status: active

## Mode

review

## Goal

Под-проекты 1–3 реализованы (SwiftUI). Под-проект 3 «Ядро генерации» завершён: ИИ-агент (ИИ-автор), этапы Черновик / Продуктовые блоки / Семантика-в-текст, версии текста (единая лента), side-by-side со стримингом и подсветкой, приём правок (всё/частично/отклонить), откат, лог запусков, настройки (ключ OpenAI + модель). Следующий шаг: план и реализация под-проекта 4 — по запросу пользователя.

## Use Superpowers

yes — writing-plans для плана следующего под-проекта, executing-plans для реализации.

## Relevant files

- docs/superpowers/specs/2026-05-19-content-system-redesign-design.md (продуктовая спека, v7.4)
- docs/superpowers/specs/2026-05-21-frontend-design.md (фронтенд-дизайн)
- docs/superpowers/plans/2026-05-21-foundation.md (под-проект 1 — выполнен)
- docs/superpowers/plans/2026-05-22-knowledge-base.md (под-проект 2 — выполнен)
- docs/superpowers/plans/2026-05-22-generation-core.md (под-проект 3 — выполнен)
- SEOContentCreator/ (Xcode-проект)

## Done criteria

- (Готово) Дизайн + фронтенд-дизайн.
- (Готово) Под-проект 1 «Фундамент».
- (Готово) Под-проект 2 «База знаний».
- (Готово) Под-проект 3 «Ядро генерации» — тесты зелёные, smoke пройден (реальная генерация OpenAI).
- (Далее) План + реализация под-проекта 4 (проверяющие этапы: Проверка SEO / Фактчекинг / Финальная вычитка, ИЛИ раздел «Шаблоны»).
- (Далее) Под-проекты 5–7.

## Agent handoff

Last agent: реализация Ядра генерации (executing-plans, TDD)

What changed: новые модели ArticleVersion, GenerationJob, StageTemplate + поля Topic (versions, jobs, currentVersionID, semantics); enum'ы PipelineStage / VersionSource / JobStatus; AI-слой (KeychainService, PromptBuilder, OpenAIClient со стримингом, StageExecutor, StageTemplateSeeder, OpenAILineParser, StageOutputParser, ParagraphDiff, VersionActions); UI (SettingsView, TopicWorkspaceView, StageBarView, SideBySideView, AcceptRejectBar + PartialAcceptSheet, VersionLaneView, JobLogView, ProductBlocksSheet, SemanticsEditorSheet). Открытие темы из контент-плана. Коммиты в main, запушено.

Smoke-фиксы (найдены при ручной проверке): выбор типа узла в Базе знаний через меню; разрешение сети для песочницы (ENABLE_OUTGOING_NETWORK_CONNECTIONS); надёжное открытие темы (кнопка «Открыть» + переключение экрана вместо вложенного navigationDestination); генерация создаёт версию-предложение, текущей становится после «Принять всё»; откат больше не задваивает версию.

Open risks: блокеров нет. UI-тестов нет (только unit). При смене схемы данных нужен сброс локального store (в этот раз удаляли default.store; реальных данных не было — на будущее, при реальных данных понадобится план миграции SwiftData). Семантика — минимальный список строк (полной сущности Semantics пока нет). Шаблоны промтов засеиваются на старте, но редактора UI нет. Diff — по абзацам (не пословный). Продуктовые блоки — стартовый фиксированный список.

Next agent should check: спеку (раздел 5 — проверяющие этапы 6–8; §2.6 SEO-рекомендации; §4.4 «Шаблоны»); план под-проекта 3 (выполнен); затем согласовать и писать план следующего под-проекта.
