# Current Task

Status: review

Allowed statuses: empty / active / review / blocked / done / paused

Stage: review

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Сделать этап «Семантика» автоматическим или полуавтоматическим. ИИ-агент формирует
списки запросов (маски, синонимы, минус-слова) для выгрузки из Yandex Wordstat,
приложение подтягивает запросы с частотностью, затем агент чистит и оценивает
список по методике сбора семантического ядра.

Реализовано полностью: все 14 задач плана (`docs/superpowers/plans/2026-07-22-semantic-autocollection.md`)
выполнены через `subagent-driven-development`, каждая прошла реализацию + проверку
соответствия спеке + проверку качества кода (с циклами исправлений там, где
находились реальные проблемы). Работа велась в изолированном worktree
`.claude/worktrees/semantic-autocollection` на ветке `worktree-semantic-autocollection`.

## Use Superpowers

yes

## Relevant files

- `docs/superpowers/specs/2026-07-22-semantic-autocollection-design.md`
- `docs/superpowers/plans/2026-07-22-semantic-autocollection.md`
- `docs/superpowers/notes/2026-07-22-wordstat-api.md` — находки по Wordstat API
- `SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift` — оркестратор
- `SEOContentCreator/SEOContentCreator/Logic/SemanticRuleFilter.swift` — слой правил
- `SEOContentCreator/SEOContentCreator/Logic/SemanticSeedPlanner.swift` — ИИ-планировщик
- `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift` — суженный анализ релевантности
- `SEOContentCreator/SEOContentCreator/Logic/SemanticCannibalizationChecker.swift` — отдельная проверка каннибализации
- `SEOContentCreator/SEOContentCreator/Logic/WordstatCloudClient.swift`, `WordstatLegacyClient.swift` — два клиента API
- `SEOContentCreator/SEOContentCreator/Views/SemanticFunnelView.swift` — экран воронки (заменил `SemanticAgentSheet`)
- `SEOContentCreator/SEOContentCreator/Views/Templates/SemanticReferenceEditorView.swift` — справочники минус-слов/масок
- `SEOContentCreator/SEOContentCreator/Views/SettingsView.swift` — учётные данные Wordstat + переключатель провайдера

## Done criteria

- [x] Реальный сбор семантики заменяет `SemanticMockKeywordCollector` (удалён).
- [x] Двухслойная очистка (правила → релевантность → каннибализация) с журналом воронки.
- [x] Два клиента Wordstat за одним интерфейсом `WordstatProvider`, переключаемые в настройках.
- [x] Экран воронки показывает по каждому слою: сколько вошло, сколько вышло и почему.
- [x] Справочники минус-слов и вопросительных масок редактируются в «Шаблонах».
- [x] Дизайн-документ утверждён и закоммичен.
- [ ] Юнит-тесты прогнаны через Cmd+U в Xcode — написаны и построчно вручную протрейсены, но реальный запуск не выполнялся (раннер `xcodebuild test` зависает в этом окружении).
- [ ] Ручной запуск приложения (Cmd+R) — открытая проверка: реальная миграция SwiftData-базы с новыми моделями (`SemanticFunnelEntry`, `SemanticStopWord`, `SemanticQueryMask`, новая связь у `Topic`) и работа экрана воронки на живом приложении.

## Agent handoff

Last agent: Claude Sonnet 5

What changed: Выполнены все 14 задач плана через `subagent-driven-development`
(диспетчеризация фреш-субагента на задачу, независимая проверка соответствия
спеке, независимая проверка качества кода, цикл исправлений при реальных
находках). 19 коммитов в ветке `worktree-semantic-autocollection`. Ключевые
решения по пути:
- Task 1 (сделана контроллером напрямую, не субагентом): один живой запрос к
  старому Wordstat API с реальным токеном пользователя показал ошибку
  TLS-сертификата (сертификат выписан на другой хост) — похоже на признак
  вывода API из эксплуатации. Пользователь решил реализовать оба варианта
  (старый OAuth + новый Yandex Cloud) за одним интерфейсом `WordstatProvider`.
- Задачи 4 и 5 (миграция SwiftData) проверены контроллером напрямую: резервная
  копия реальной базы, пересборка, запуск бинарника, сверка таблиц/контрольных
  сумм — данные не пострадали, но полноценный запуск с окном подтвердить в этом
  headless-окружении не удалось (SwiftUI `.modelContainer` не инициализируется
  без реальной оконной сессии).
- Несколько раундов code review нашли и исправили реальные проблемы: тихое
  исчезновение пустых/дублирующихся фраз без причины (Task 3), потерянное
  сообщение реальной ошибки при неудачном запросе к Wordstat (Task 11),
  устаревший текст про каннибализацию и непрокомментированный stopgap (Task 8),
  непротестированная логика определения TLS-сбоя (Task 10), устаревшая подпись
  кнопки после замены экрана (Task 12).

Open risks:
- Форма ответа старого Wordstat API не подтверждена (запрос не дошёл до тела
  ответа) — `WordstatLegacyClient` использует парсер нового API как
  предположение, явно помеченное в коде и плане.
- Полный запуск приложения с реальной базой пользователя не проверен вживую
  (headless-ограничение сессии) — нужен один Cmd+R и один прогон Cmd+U перед
  тем, как считать задачу окончательно закрытой.
- Мелкий незакрытый полиш (не блокирует): поиск и меню «Добавить» в «Шаблонах»
  бездействуют на вкладке «Семантика» (Task 13); нет кнопки удаления для трёх
  новых полей в Настройках (Task 14) — оба согласованы с существующими
  паттернами экрана, не новые проблемы.

Next agent should check: пользователь должен открыть приложение в Xcode,
прогнать тесты через Cmd+U и один раз запустить сбор семантики на реальной
теме (Cmd+R), прежде чем `task-finish`. После этого — предложить слияние через
`superpowers:finishing-a-development-branch`.
