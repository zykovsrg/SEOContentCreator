# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: spec

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Реализовать полноценную поддержку задачи читателя через поисковый интент: хранить и редактировать данные в теме, использовать семантику как ориентир при построении структуры, передавать компактный контекст нужным этапам без перегрузки и сделать сохранённый пользователем промт новым защищённым дефолтом.

## Use Superpowers

yes

## Relevant files

- Пользовательское вложение `pasted-text.txt` с шаблоном интента.
- `SEOContentCreator/SEOContentCreator/Logic/StageTemplateDefaults.swift`
- `SEOContentCreator/SEOContentCreator/Logic/PromptBuilder.swift`
- `SEOContentCreator/SEOContentCreator/Logic/RoleDefaults.swift`
- `SEOContentCreator/SEOContentCreator/Logic/StageTemplateSeeder.swift`
- `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- `SEOContentCreator/SEOContentCreator/Views/BriefView.swift`
- `SEOContentCreator/SEOContentCreator/Logic/TemplateVariables.swift`
- `SEOContentCreator/SEOContentCreator/Views/Templates/StagePromptEditorView.swift`
- Тесты моделей, сборки промтов, дефолтов, миграций и UI-логики — уточнить по плану.

## Done criteria

- У темы есть отдельные сохраняемые данные о задаче читателя; существующие темы открываются без потери данных.
- Пользователь может просмотреть и отредактировать задачу читателя в брифе.
- Этап «Структура» получает семантику как ориентир для определения интента, а не как список обязательных ключей.
- Актуальные модифицированные промты расширены точечно: карта задачи передаётся только нужным этапам, без копирования полной методички.
- SEO-проверка оценивает соответствие интенту и полноту ответа; фактчекинг и нерелевантные этапы не перегружены.
- Нажатие «Сохранить» в редакторе промта делает сохранённую версию пользовательским дефолтом: она используется в работе, восстанавливается кнопкой сброса и не затирается последующими миграциями стандартных промтов.
- Добавлены тесты для новой модели данных, подстановок, дефолтов/миграций и изменённого поведения сохранения; релевантные проверки проходят.

## Agent handoff

Last agent: Codex

What changed: Аналитическая задача по явному подтверждению пользователя расширена до полной реализации с изменением данных, UI, промтов и поведения пользовательского дефолта.


Open risks: SwiftData-совместимость существующей базы; сохранение уже модифицированных промтов; точная семантика пользовательского дефолта и кнопки сброса; недопущение лишнего контекста в нерелевантных этапах.


Next agent should check: Текущий код StagePromptEditorView/StageTemplateSeeder и тесты миграций до выбора структуры данных пользовательского дефолта.
