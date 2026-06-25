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

### FT-20260623-001 — Полноценная Семантика: частотность, статусы, индикатор

Status: idea

Priority: medium

Source: анализ спеки 2026-06-23 (раздел 2.2, 4.1, 5 шаг 1)

Created: 2026-06-23

Context:

Текущая реализация Семантики — простой `TextEditor` с построчным списком запросов (`[String]`). Спека описывает полноценную таблицу.

Proposed task:

1. Заменить `Topic.semantics: [String]` на `[SemanticKeyword]` (SwiftData-сущность: текст, частотность `Int?`, статус `included/excluded/required`). Изменение схемы — согласовать миграцию.
2. UI: таблица в `SemanticsEditorSheet` с редактируемыми ячейками, переключением статуса.
3. Опциональная группировка (текстовая метка).
4. Индикатор «семантика собрана» в Контент-плане (строка темы).
5. Фильтрация по статусу в `{{семантика}}` — в промт попадают только `included` и `required`; обязательные выделяются явно.

Acceptance criteria:

- Существующие темы не теряют свои запросы (миграция).
- `{{семантика}}` в промте передаёт только нужные запросы с учётом статуса.
- В Контент-плане виден индикатор.

Promotion notes:

- Изменение SwiftData-схемы — сначала объяснить пользователю риск и путь миграции.
- Топвизор-импорт — в спеке «осознанно отложен»; не включать в этот scope.

---

### FT-20260623-002 — Продуктовые блоки из Базы знаний

Status: idea

Priority: low

Source: анализ спеки 2026-06-23 (раздел 2.7, 4.4, 5 шаг 4)

Created: 2026-06-23

Context:

`ProductBlocksSheet` сейчас содержит жёсткий список из 4 блоков и не связан с Базой знаний. Комментарий в коде: «refined in a later sub-project».

Proposed task:

1. Добавить редактируемые шаблоны продуктовых блоков в раздел «Шаблоны» (категория «Продуктовые блоки»).
2. В `ProductBlocksSheet` список формируется из этих шаблонов, а не хардкода.
3. Переменные блоков (`{{врач_данные}}`, `{{преимущества}}`) берут данные из прикреплённых узлов Базы знаний темы.
4. При генерации блок встраивается в текст через `StageExecutor`.

Acceptance criteria:

- Шаблоны продуктовых блоков редактируются в «Шаблонах».
- Данные врача/преимуществ подставляются из Базы знаний, а не выдумываются ИИ.

Promotion notes:

- Сначала убедиться, что KnowledgeNode-узлы прикрепляются к теме и доступны в промт-билдере.

---

### FT-20260623-003 — Сквозные инструменты ручной правки: скиллы, регенерация фрагмента, мягкие подсказки

Status: done (п.3 мягкие подсказки — done 2026-06-24, в main; пп.1 пресеты скиллов и 2 регенерация фрагмента — done 2026-06-25, ветка feature/fragment-edit-skills)

Priority: medium

Source: анализ спеки 2026-06-23 (раздел 2.8, 7)

Created: 2026-06-23

Context:

Три связанных инструмента из раздела 7 спеки не реализованы. Все они работают с выделенным фрагментом текста в рабочем пространстве темы.

Proposed task:

1. **Пресеты скиллов** — библиотека мини-промтов для выделенного фрагмента («перепиши в инфостиле», «упрости», «уточни», «убери канцелярит»). Редактируется в «Шаблонах». Применение: выделить → выбрать скилл → локальный side-by-side → принять/отклонить → новая версия.
2. **Регенерация фрагмента** — выделить произвольный кусок → ввести комментарий «что не нравится» → агент ИИ-автор регенерирует только этот фрагмент → side-by-side → принять.
3. **Мягкие алгоритмические подсказки** — без ИИ: подчёркивание длинных предложений (по порогу), повторов однокоренных слов рядом, штампов по редактируемому словарю. Словарь пополняется вручную (в «Шаблонах»). Не дублирует «Финальную вычитку» — грубые и мгновенные.

Acceptance criteria:

- Скиллы применяются к фрагменту и создают версию.
- Регенерация фрагмента меняет только выделенный участок.
- Мягкие подсказки видны при редактировании, не блокируют сохранение.

Promotion notes:

- Начать с пресетов скиллов как наиболее самодостаточной части.
- Регенерация фрагмента требует выделения текста в SwiftUI — оценить возможности `TextEditor` или альтернативы.
- Мягкие подсказки — отдельный scope, не смешивать с двумя первыми.

---

### FT-20260623-004 — Режим «Быстрая проверка»

Status: idea

Priority: low

Source: анализ спеки 2026-06-23 (раздел 5, «Режим Быстрая проверка»)

Created: 2026-06-23

Context:

Отдельное окно для разовых задач без создания темы. Вставить текст, выбрать одну проверку, получить side-by-side. Результат скопировать или сохранить как тему.

Proposed task:

1. Новое sheet/window: TextEditor для ввода текста, Picker проверки (Фактчекинг / Финальная вычитка / Проверка SEO).
2. Запуск — тот же `StageExecutor`, но без привязки к теме.
3. Результат — side-by-side diff + список замечаний (как в обычных этапах).
4. Кнопки: «Скопировать результат», «Сохранить как тему».

Acceptance criteria:

- Работает без создания темы.
- Результат не сохраняется автоматически.

Promotion notes:

- Нет изменений SwiftData-схемы.
- Переиспользует существующий `StageExecutor` и отображение замечаний.

---

### FT-20260623-005 — Сравнение двух версий из ленты (side-by-side diff)

Status: idea

Priority: medium

Source: анализ спеки 2026-06-23 (раздел 2.3, 4.2)

Created: 2026-06-23

Context:

В спеке: выбрать две версии из ленты → side-by-side diff. Сейчас сравнение доступно только при принятии результата этапа (новая vs текущая). Произвольное сравнение двух исторических версий не реализовано.

Proposed task:

1. В ленте версий (`VersionHistoryView`) добавить режим выбора двух версий.
2. Открыть существующий `ParagraphDiff`-движок на выбранной паре.
3. Только просмотр, без возможности принятия (либо «откатить к этой версии»).

Acceptance criteria:

- Редактор может выбрать любые две версии и сравнить их.
- `ParagraphDiff` отображает изменения корректно.

Promotion notes:

- `ParagraphDiff` уже реализован — переиспользовать.

---

### FT-20260623-006 — Стоимость по теме в Контент-плане

Status: idea

Priority: low

Source: анализ спеки 2026-06-23 (раздел 4.1)

Created: 2026-06-23

Context:

Спека: в Контент-плане колонка «Стоимость по теме» (сумма токенов всех `GenerationJob` для темы). Данные уже хранятся в `GenerationJob`.

Proposed task:

1. Добавить вычисляемое свойство `Topic.totalTokenCost` — сумма токенов по всем `GenerationJob`.
2. Отобразить в строке темы в Контент-плане (опционально: только в расширенном режиме).

Acceptance criteria:

- Стоимость обновляется после каждого запуска этапа.

Promotion notes:

- Низкий риск — только чтение существующих данных.
- Нет изменений схемы.

---

### FT-20260623-007 — Инструменты шаблонов: песочница + импорт/экспорт + резервное копирование

Status: idea

Priority: low

Source: анализ спеки 2026-06-23 (разделы 4.4, 13)

Created: 2026-06-23

Context:

Три связанных функции из «Расширенного режима» спеки, которые повышают безопасность и удобство работы с шаблонами.

Proposed task:

1. **Песочница шаблонов** — запустить шаблон на выбранной теме без сохранения результата как текущей версии. Результат виден в отдельном окне.
2. **Импорт/экспорт шаблонов** — экспорт всего набора шаблонов в JSON-файл, импорт из файла с заменой или слиянием.
3. **Резервное копирование** — локальный экспорт всей SwiftData-базы в JSON/архив. Опциональный авто-бэкап по расписанию.

Acceptance criteria:

- Песочница не меняет ленту версий.
- Импорт не ломает существующие шаблоны (предупреждение о перезаписи).
- Экспорт/импорт резервной копии работает без потери данных.

Promotion notes:

- Реализовывать по одному пункту — не смешивать.
- Резервное копирование — наибольший риск (SwiftData export API); оценить перед началом.

---

### FT-20260623-008 — Расширенный режим (тумблер, скрывающий power-user функции)

Status: idea

Priority: low

Source: анализ спеки 2026-06-23 (раздел 4.5)

Created: 2026-06-23

Context:

Спека предусматривает тумблер «Показать расширенные функции» в Настройках. По умолчанию скрывает: параметры моделей в шаблонах (модель, температура, max tokens), полные логи с токенами и стоимостью, создание новых типов статей.

Proposed task:

1. Добавить `@AppStorage("advancedMode") var advancedMode: Bool = false` + тумблер в `SettingsView`.
2. В `TemplatesView` и других местах прятать power-user контролы за этим флагом.

Acceptance criteria:

- При выключенном режиме новичок не видит параметры моделей и сложные настройки.
- При включённом — всё доступно как сейчас.

Promotion notes:

- Чисто UI-изменение, нет изменений схемы.
- Не скрывать за флагом то, что нужно в ежедневной работе.

---

### FT-20260621-001 — Выбор «интенсивности мышления» (reasoning_effort) для моделей GPT-5 / o-серии

Status: promoted (→ ai/current-task.md, 2026-06-23)

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
