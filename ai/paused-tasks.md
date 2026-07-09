# Paused Tasks

Use this file only when an unfinished task is intentionally paused through `task-switch`.

Do not use it as a backlog.

Keep entries short.

## Template

### YYYY-MM-DD — Task title

Status: paused

Why paused:

Current state:

Relevant files:

Open risks:

Resume criteria:

## Paused tasks

### 2026-07-09 — Inspector layout and bottom action labels

Status: paused

Why paused: пользователь попросил продолжить редизайн и добавить настройки
модели/мышления для каждого этапа до закрытия предыдущей маленькой правки.

Current state: `TopicWorkspaceView.swift` уже поправлен: правый inspector
выравнивается сверху и тянется на высоту панели, нижние кнопки резервируют
ширину для подписей. Build-for-testing, Release build, установка в
`/Applications` и `codesign --verify` уже проходили успешно.

Relevant files:
- `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

Open risks: нужна только финальная визуальная проверка в установленном
приложении, если пользователь захочет отдельно закрыть эту правку.

Resume criteria: пользователь просит закрыть предыдущую задачу или проверить
экран работы над темой.

### 2026-07-04 — Аудит всех LLM-промптов приложения

Status: paused

Why paused: пользователь попросил переключиться на новую задачу (объединение
режима «Ручная правка» и «Правка фрагмента»); подтвердил постановку аудита на
паузу через `task-switch`.

Current state: задача была только записана через `task-intake` (режим review,
без изменений кода). Реальная работа по аудиту — чтение шаблонов промптов,
`PromptBuilder`, пайплайна этапов — ещё не начиналась, находок нет.

Relevant files: unknown (предстояло найти) — шаблоны промптов, PromptBuilder,
исходники пайплайна этапов.

Open risks: нет (read-only ревью, код не менялся).

Resume criteria: пользователь просит вернуться к аудиту промптов; тогда
начать с поиска `PromptBuilder`, `StageTemplate*`, `Logic/*Prompt*` и
пройтись по каждому этапу пайплайна.

### 2026-07-03 — Тормоза UI при длинной генерации

Status: paused

Why paused: пользователь попросил переключиться на новую задачу (ручное добавление семантики).

Current state: 3 фикса не помогли (кэш парсинга Markdown, троттлинг streamingText, обрезка
"хвоста" текста). Сейчас добавляются диагностические Logger-метки (без изменения поведения) в
двух точках — сетевой слой (OpenAIClient) и MainActor-цикл (StageExecutor) — чтобы понять, где
именно растёт задержка между получением токена от сети и его обработкой на MainActor.

Relevant files:
- Logic/OpenAIClient.swift (точка замера №1, сетевой слой)
- Logic/StageExecutor.swift (точка замера №2, MainActor; 3 цикла стриминга)
- Views/SideBySideView.swift (fix #3, оставлен — не мешает)

Open risks: если сопоставление логов не даст чёткой картины — понадобится профилирование через
Instruments (Time Profiler) во время живой генерации.

Resume criteria: пользователь просит вернуться к отладке тормозов; тогда снять живой лог через
`log stream --predicate 'subsystem == "com.zykovsrg.SEOContentCreator"'` во время генерации и
сопоставить интервалы сеть vs MainActor.
