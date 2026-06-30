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

### FT-20260626-003 — Стабильная подпись приложения, чтобы Keychain не спрашивал пароль каждый раз

Status: idea

Priority: medium

Source: вопрос пользователя 2026-06-26 (промпт Keychain при каждом запуске/тестах)

Created: 2026-06-26

Context:

При каждой пересборке Xcode подписывает приложение заново (ad-hoc подпись со свежим хешем), поэтому macOS считает бинарник «новым» и снова просит пароль login-keychain для доступа к записи `SEOContentCreator.OpenAI` (см. `Logic/KeychainService.swift`). Кнопка «Always Allow» помогает только до следующей сборки. На тестах хуже: каждый прогон — новый бинарник. Продакшн-код уже изолирован от Keychain через `keyProvider`-замыкание (`StageExecutor`/`ImageGenerator`/`FragmentEditor`); реально в системный Keychain ходят только `KeychainServiceTests` (3 теста, тестируют саму обёртку) и само приложение.

Proposed task:

1. **Шаг 1 (основной, настройка в Xcode, делает пользователь):** target `SEOContentCreator` → Signing & Capabilities → выбрать Team (личный Apple ID / Personal Team) + Automatically manage signing. Стабильная подпись → ACL в Keychain не сбрасывается → одного «Always Allow» хватает надолго и для приложения, и для тестового раннера.
2. **Шаг 2 (опционально, правка кода):** добавить capability Keychain Sharing и читать/писать ключ с флагом `kSecUseDataProtectionKeychain` в `KeychainService` — доступ привязывается к Team ID, а не к бинарнику, промпт уходит совсем. Требует Team из шага 1. Изменение в работе с хранилищем — объяснить риски заранее.
3. **Шаг 3 (опционально, тесты):** гейт для `KeychainServiceTests` по переменной окружения (например `RUN_KEYCHAIN_TESTS=1`), чтобы в обычном Cmd+U эти 3 теста пропускались и не всплывал пароль.

Acceptance criteria:

- После шага 1 приложение и тесты перестают спрашивать пароль login-keychain при каждой сборке (после однократного «Always Allow»).

Promotion notes:

- Шаг 1 — это настройка в окне Xcode, не правка кода; код менять не нужно.
- НЕ открывать запись «для всех приложений» (`SecAccessCreate` с пустым списком доверия) — снижает безопасность ключа OpenAI; правильный путь — data-protection keychain (шаг 2).
- Шаги 2 и 3 — отдельные scope, не смешивать.
