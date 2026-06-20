# Future Tasks

Use this file for ideas and future implementation tasks that are not part of the current task scope.

This is a backlog, not active work.

## Rules

- Do not implement these tasks unless the user explicitly promotes one to the current task.
- Do not use this file for paused active work. Use `ai/paused-tasks.md` for interrupted unfinished tasks.
- Do not use this file for completed change history. Use `ai/changelog.md` for what changed.
- Do not use this file for durable architecture or product decisions. Use `ai/decisions.md` for rules future agents must not break.
- Keep entries short, actionable, and linked to the context where they appeared.
- If a future task becomes active, copy it into `ai/current-task.md` and mark the original entry as `promoted`.

## Statuses

```text
idea / ready / blocked / promoted / done / dropped
```

## Template

### FT-YYYYMMDD-001 — Task title

Status: idea

Priority: low / medium / high

Source: where the idea appeared

Created: YYYY-MM-DD

Context:

Short context: why this may be useful later.

Proposed task:

What should be implemented later.

Acceptance criteria:

- How to know this future task is done.

Promotion notes:

What to check before moving this task to `ai/current-task.md`.

## Future tasks

### FT-20260621-001 — Выбор «интенсивности мышления» (reasoning_effort) для моделей GPT-5 / o-серии

Status: ready

Priority: medium

Source: запрос пользователя 2026-06-21

Created: 2026-06-21

Context:

Для моделей OpenAI семейства GPT-5 / o-серии есть параметр `reasoning_effort` («интенсивность мышления»: low/medium/high). Сейчас приложение его не передаёт. Затрагиваемые файлы:
- `SEOContentCreator/SEOContentCreator/Logic/OpenAIClient.swift` — сборка тела запроса в `streamCompletion(...)` (строки ~64–80); уже есть ветка `if usesMaxCompletionTokens(model:)` для новых моделей (gpt-5.x / o1 / o3 / o4) — добавлять туда.
- `SEOContentCreator/SEOContentCreator/Models/StageTemplate.swift` — настройки модели у этапа (`modelName`, `temperature`, `maxTokens`). **Персистентная модель (SwiftData) — изменение схемы.**
- `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift` — проброс значений в клиент (вызов ~строка 77).
- `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift` — редактирование шаблонов.

Proposed task:

1. **Данные:** добавить в `StageTemplate` опциональное поле `reasoningEffort: String?` (значения "low"/"medium"/"high"; `nil` = не передавать параметр / поведение по умолчанию). Так как это изменение схемы SwiftData — сначала объяснить пользователю риск и совместимость со старыми шаблонами (поле опциональное, default `nil` → лёгкая миграция).
2. **OpenAIClient.streamCompletion:** добавить параметр `reasoningEffort: String? = nil`. Если модель попадает под `usesMaxCompletionTokens(model:)` И `reasoningEffort != nil` — добавить в тело запроса `"reasoning_effort"`. Для старых моделей (gpt-4.x и т.п.) не передавать. Не ломать текущую логику `temperature`/`max_tokens`.
3. **StageExecutor:** пробросить значение из шаблона в клиент.
4. **UI (TemplatesView):** Picker уровня (Low / Medium / High / «по умолчанию») рядом с выбором модели; показывать и применять только для моделей GPT-5 / o-серии (переиспользовать `OpenAIClient.usesMaxCompletionTokens`). Тексты на русском.
5. **Тесты:** дополнить `OpenAIClientTests.swift` — `reasoning_effort` попадает в тело для GPT-5 модели и НЕ попадает для старой модели и при `nil`.

Acceptance criteria:

- Для GPT-5/o-модели с выбранным уровнем `reasoning_effort` уходит в запрос; для старых моделей и при «по умолчанию» — нет.
- Старые сохранённые шаблоны открываются без потери данных (миграция прошла).
- `xcodebuild build-for-testing` зелёный; тесты в Xcode (Cmd+U) зелёные.

Promotion notes:

- Сначала режим review/план; изменение схемы `StageTemplate` согласовать с пользователем ДО правок.
- Имя модели не хардкодить (например, «gpt-5.5») — модель выбирает пользователь, `reasoningEffort` отдельное поле.
- Минимальные диффы, не смешивать с другими изменениями, не расширять scope.
- Проверка сборки: `xcodebuild build-for-testing` (CLI `xcodebuild test` зависает — тесты через Cmd+U).
