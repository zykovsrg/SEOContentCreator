# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: review

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Реализовать FT-20260623-003 пп.1–2 — сквозные инструменты ручной правки на выделенном фрагменте текста в рабочем пространстве темы:

1. **Пресеты скиллов** — библиотека мини-промтов для выделенного фрагмента («перепиши в инфостиле», «упрости», «уточни», «убери канцелярит»), редактируется в «Шаблонах». Применение: выделить → выбрать скилл → локальный side-by-side → принять/отклонить → новая версия.
2. **Регенерация фрагмента** — выделить произвольный кусок → ввести комментарий «что не нравится» → ИИ-автор регенерирует только этот фрагмент → side-by-side → принять.

Промоутнуто из ai/future-tasks.md (FT-20260623-003 пп.1–2) 2026-06-24. Пункт 3 (мягкие подсказки) уже завершён и в main.

По промоут-нотам: начать с п.1 (наиболее самодостаточен); для п.2 сначала оценить, как выделять произвольный фрагмент в SwiftUI (TextEditor или альтернатива). Уже существует переменная `{{выделенный_фрагмент}}` (из под-проекта 8) — переиспользовать.

## Use Superpowers

yes

## Spec

docs/superpowers/specs/2026-06-24-fragment-edit-skills-design.md (согласован пользователем 2026-06-24)

## Relevant files

unknown — кандидаты: Views/TopicWorkspaceView.swift (тулбар/выделение), Views/TemplatesView.swift (редактор скиллов), Logic/StageExecutor.swift (запуск ИИ-автора на фрагменте), Logic/PromptBuilder.swift + TemplateVariables ({{выделенный_фрагмент}}), новая SwiftData-модель для пресетов скиллов (изменение схемы — согласовать).

## Done criteria

- Скиллы применяются к выделенному фрагменту и создают версию.
- Регенерация фрагмента меняет только выделенный участок, side-by-side, приём создаёт версию.
- Пресеты скиллов редактируются в «Шаблонах», сброс к стандартному работает.
- Существующие данные не теряются.
- xcodebuild build-for-testing зелёный; тесты зелёные в Xcode (Cmd+U).

## Agent handoff

Last agent: Claude (opus-4-8)

What changed: вся фича пп.1–2 реализована по плану (subagent-driven для Tasks 1–8, Task 9 доделан инлайн после лимита сессии). Ветка feature/fragment-edit-skills, 9 коммитов aa541af..5db3d01. Новые: SkillPreset (+defaults/seeder), FragmentSplicer, FragmentPromptBuilder, FragmentEditor, FragmentEditSheet; изменены VersionSource, ArticleVersion, схема, RootView, TopicWorkspaceView (кнопка «Правка фрагмента»), TemplatesView (раздел «Скиллы»). Тесты: FragmentEditTests.swift. `xcodebuild build-for-testing` — TEST BUILD SUCCEEDED.

Open risks: тесты НЕ прогнаны headless (CLI test зависает) — пользователь должен запустить Cmd+U. Ветка не запушена, в main не влита. Замена фрагмента по строке — снимается проверкой уникальности (FragmentSplicer).

Next agent should check: после зелёного Cmd+U — task-finish (changelog, decisions, push ветки, опц. PR). Спека: docs/superpowers/specs/2026-06-24-fragment-edit-skills-design.md; план: docs/superpowers/plans/2026-06-24-fragment-edit-skills.md.
