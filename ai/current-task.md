# Current Task

Status: empty

Allowed statuses: empty / active / review / blocked / done / paused

Stage: task-finish

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Реализовать FT-20260623-003 — **только пункт 3** (мягкие алгоритмические подсказки), по решению пользователя 2026-06-24. Пункты 1 (пресеты скиллов) и 2 (регенерация фрагмента) остаются в future-tasks на потом.

Мягкие алгоритмические подсказки без ИИ на тексте темы:
- длинные предложения (по порогу);
- повторы однокоренных слов рядом;
- штампы по редактируемому словарю.

Подсказки видны при просмотре текста (отдельный sheet), не блокируют сохранение, грубые и мгновенные. Не дублируют «Финальную вычитку». Словарь штампов пополняется вручную в «Шаблонах».

Промоутнуто из ai/future-tasks.md (FT-20260623-003) 2026-06-24.

## Use Superpowers

yes

## Spec

docs/superpowers/specs/2026-06-24-soft-editing-hints-design.md (согласован пользователем 2026-06-24)

## Relevant files

Новые: Logic/SoftHints.swift, Models/EditorDictionary.swift, Logic/EditorDictionarySeeder.swift, Views/SoftHintsSheet.swift, Views/MultiHighlightedText.swift, Tests/SoftHintsTests.swift.
Изменяемые: Views/TopicWorkspaceView.swift, Views/TemplatesView.swift, SEOContentCreatorApp.swift:10 (schema), RootView.swift:22 (seeder).

## Done criteria

- «Подсказки» открывают окно с подсветкой длинных предложений, повторов однокоренных и штампов на тексте текущей версии.
- Словарь штампов и пороги редактируются в «Шаблонах», сброс к стандартному работает.
- Подсказки ничего не сохраняют и не блокируют работу.
- Существующие данные не теряются (новая модель — без миграции существующих).
- `xcodebuild build-for-testing` зелёный; тесты `SoftHints` зелёные в Xcode (Cmd+U).

## Agent handoff

Last agent: Claude (opus-4-8)

What changed: вся фича реализована по плану через subagent-driven dev (8 коммитов d685887..6a75efd). SoftHints-анализатор + 14 тестов, модель EditorDictionary + сидер, MultiHighlightedText, SoftHintsSheet, кнопка «Подсказки» в рабочем пространстве, редактор «Словарь правок» в «Шаблонах». Независимая сборка `xcodebuild build-for-testing` — BUILD SUCCEEDED.

Open risks: тесты SoftHints НЕ прогнаны headless (CLI test зависает) — пользователь должен запустить Cmd+U. Префиксный детектор однокоренных — грубый (приемлемо по спеке).

Next agent should check: после зелёного Cmd+U — task-finish (changelog, push ветки, опц. PR). Ничего не запушено.
