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
