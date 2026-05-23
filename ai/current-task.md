# Current Task

Status: idle

## Mode

review

## Goal

Текущая задача закрыта. Под-проекты 1–6 реализованы и проверены:

- Под-проект 1 «Фундамент».
- Под-проект 2 «База знаний».
- Под-проект 3 «Ядро генерации».
- Под-проект 4 «Проверяющие этапы».
- Под-проект 5 «Редактор промтов этапов» (срез A раздела «Шаблоны») + багфикс GPT-5/o-series.
- Под-проект 6 «ИИ-роли и блоки контекста» (срез B раздела «Шаблоны»), коммит `08c2f0c`, запушено в `main`.

Новая задача ещё не выбрана.

## Use Superpowers

no — включать только по явному запросу пользователя или если следующая задача будет крупной, архитектурной, TDD-heavy, migration-heavy, subagent-heavy или с неясным blast radius.

## Relevant files

- `SEOContentCreator/` — Xcode-проект.
- `ai/project-context.md` — команды сборки/тестов и контекст проекта.
- `ai/changelog.md` — история последних завершённых под-проектов.
- `ai/decisions.md` — активные архитектурные и продуктовые решения.
- `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md` — продуктовая спека.
- `docs/superpowers/specs/2026-05-23-ai-roles-design.md` — спека под-проекта 6.

## Done criteria

Нет активной задачи. Для следующей задачи пользователь должен задать:

- Mode: `implementation` / `review` / `task-finish` / `architecture-update`.
- Goal: что должно измениться.
- Relevant files: известные файлы или `unknown`.
- Done criteria: как понять, что задача готова.

## Agent handoff

Last completed task: под-проект 6 «ИИ-роли и блоки контекста».

What changed:

- Добавлены редактируемые `AIRole` и `ContextBlock`.
- Добавлены дефолты ролей/блоков и `RoleContextAssembler`.
- `PromptBuilder` собирает system prompt из `roleContext + template.systemPrompt`.
- `StageExecutor` берёт роль по `PipelineStage.roleKey`, подставляет блоки и сохраняет имя роли как снимок для новых запусков.
- `StageTemplateSeeder` засевает роли/блоки и мигрирует старые systemPrompt до коротких дефолтов через `templatesDefaultsVersion = 2`.
- `TemplatesView` получил категории «Промты этапов», «ИИ-роли», «Редполитика и источники».
- `StageBarView` показывает имя роли из `AIRole.name`.

Verification:

- `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /private/tmp/SEOContentCreatorDerivedData OTHER_SWIFT_FLAGS='-disable-sandbox'` — зелёный в Codex.
- `xcodebuild -scheme SEOContentCreator -destination 'platform=macOS' build -derivedDataPath /private/tmp/SEOContentCreatorDerivedData OTHER_SWIFT_FLAGS='-disable-sandbox'` — зелёный в Codex.
- Cmd+U в Xcode: unit-тесты зелёные — 87 tests / 25 suites; UI-тесты зелёные — 4 tests.
- Smoke пользователем пройден.

Open risks:

- В Codex CLI тест-раннер macOS не запускается из-за sandbox/testmanagerd; проверять реальные тесты через Cmd+U в Xcode.
- Часть GPT-5-моделей может давать HTTP 404 из-за доступа аккаунта OpenAI; рабочие модели: `gpt-4.1`, `gpt-4o`.
- Остались будущие срезы «Шаблонов» C–E (типы статей, продуктовые блоки, скиллы/песочница), а также возможные будущие под-проекты: этап «Стиль», полная «Семантика», очередь, публикация в Google Docs.
