# Current Task

Status: in-progress (передано внешнему агенту Codex)

## Mode

implementation

## Goal

Под-проект 8 «Генерация изображений»: обложка + иллюстрации + библиотека пресетов стиля + доработка картинки промтом. Через OpenAI images API (имя модели настраиваемое: gpt-image-1 / gpt-image-2).

Спека и план готовы и закоммичены; реализация — в Codex по плану, задача за задачей (TDD).

## Use Superpowers

yes — brainstorming + writing-plans уже пройдены (проектирование в Claude). Реализация — в Codex.

## Relevant files

- Спека: `docs/superpowers/specs/2026-05-24-images-design.md` (коммит `1380b98`).
- План (17 задач, пошагово): `docs/superpowers/plans/2026-05-24-images.md` (коммит `a01758d`).
- Новые модели: `GeneratedImage`, `ImageStylePreset`, `ImagePromptTemplate`; изменения `Topic` (`images`, `coverImageID`).
- Логика: `ImageClient`, `ImageGenerator`, `ImageSaver`, `ImagePromptBuilder`, `ImagePromptDefaults`, `ImageStylePresetDefaults`; засев в `StageTemplateSeeder`; переменная `{{выделенный_фрагмент}}`.
- UI: `ImageGenerationSheet`, `ImagesView` + панель в `TopicWorkspaceView`; категория «Изображения» в `TemplatesView`; поле image-модели в `SettingsView`.

## Done criteria

- Все 17 задач плана выполнены; `xcodebuild build-for-testing` зелёный.
- Юнит-тесты зелёные (Cmd+U, пользователь): новые сюиты Image*Tests + расширенные TemplateVariables/GenerationJob.
- Smoke (Cmd+R, реальный ключ): генерация обложки и иллюстрации (вставка фрагмента), сохранение в галерею, доработка промтом, «Сделать обложкой», экспорт PNG, архив; правка шаблонов/пресетов в «Шаблонах»; путь ошибки при неверном ключе.

## Agent handoff

Решения по дизайну (согласованы с пользователем):
- Провайдер — OpenAI images API; имя модели настраиваемое (gpt-image-1 / gpt-image-2).
- Картинки — галерея у `Topic`, отдельно от ленты текстовых версий; текст чистый.
- Иллюстрация помнит место якорем-цитатой выделенного фрагмента (для будущей вставки в Docs).
- Стиль — библиотека редактируемых пресетов (стиль-текст + опц. референс-картинка + размер/качество); дефолтный брендовый пресет с палитрой #F4F9FF/#E8F1FF/#D9E8FD/#007AC0, «без текста», «для пациентов».
- Сюжет — шаблон промта с переменными (`{{тема}}`, `{{выделенный_фрагмент}}`), фрагмент вставляется вручную в окне; финальный промт = шаблон + styleText пресета.
- Доработка — только промтом (без маски/inpainting); новая картинка с `sourceImageID`, исходник не затирается.

Workflow: проектирование в Claude, реализация в Codex (хэндофф-промт выдан). Codex собирает с `OTHER_SWIFT_FLAGS=-disable-sandbox`; CLI `xcodebuild test` зависает → тесты прогоняет пользователь в Xcode (Cmd+U).

Open risks:
- `gpt-image-2` вышла после среза знаний ассистента (август 2025): точные параметры images API (имена полей, значения quality, multipart для edits) сверить с актуальной докой OpenAI при реализации. Вынесено в настройки/пресет → правка конфигурации, не архитектуры.
- Вставка картинок в Google Docs — будущий этап «Публикация», в объём не входит (сейчас только якорь + экспорт PNG).
- `@Attribute(.externalStorage)` у `GeneratedImage.data` — следить за объёмом при множестве картинок (архивация вместо удаления).

Вне объёма под-проекта 8: вставка в Docs, захват выделения из редактора, маска/inpainting, апскейл/вариации, серийная авто-генерация, встраивание картинок в markdown версий.
