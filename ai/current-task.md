# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: implementation

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Сделать этап «Семантика» автоматическим или полуавтоматическим. ИИ-агент формирует
списки запросов (маски, синонимы, минус-слова) для выгрузки из Yandex Wordstat,
приложение подтягивает запросы с частотностью, затем агент чистит и оценивает
список по методике сбора семантического ядра.

Сейчас реального сбора нет: `SemanticMockKeywordCollector` клеит шаблоны вида
«тема + лечение», а `SemanticAgentAnalyzer` оценивает эти выдуманные кандидаты без
частотности.

Дизайн и план реализации утверждены и закоммичены. Реализация идёт в изолированном
worktree (`.claude/worktrees/semantic-autocollection`, ветка
`worktree-semantic-autocollection`) через `subagent-driven-development`, по 15
задачам плана.

## Use Superpowers

yes

## Relevant files

- `docs/superpowers/specs/2026-07-22-semantic-autocollection-design.md`
- `docs/superpowers/plans/2026-07-22-semantic-autocollection.md` — источник истины по 15 задачам
- `docs/superpowers/notes/2026-07-22-wordstat-api.md` — находки по Task 1
- `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift` — удаляется в Task 12
- `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`
- `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift`
- `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift` — заменяется в Task 12

## Done criteria

Все 15 задач плана выполнены, каждая с зелёными тестами (Cmd+U) и коммитом:

- Реальный сбор семантики заменяет `SemanticMockKeywordCollector`.
- Двухслойная очистка (правила → релевантность → каннибализация) с журналом воронки.
- Два клиента Wordstat за одним интерфейсом `WordstatProvider` — старый OAuth
  (`api.wordstat.yandex.net`, сейчас не работает — TLS-сертификат не совпадает
  с именем хоста, см. заметку) и новый Yandex Cloud (API-ключ + folderId),
  переключаемые в настройках.
- Экран воронки показывает по каждому слою: сколько вошло, сколько вышло и почему.
- Справочники минус-слов и вопросительных масок редактируются в «Шаблонах».
- Итоговая проверка через `superpowers:finishing-a-development-branch`.

## Agent handoff

Last agent: Claude Sonnet 5

What changed: создан изолированный worktree
(`.claude/worktrees/semantic-autocollection`). Выполнена Task 1 плана — прочитана
документация Wordstat API, сделан один живой запрос по OAuth-токену пользователя.
Найдено: соединение падает на проверке TLS-сертификата (сертификат выписан на
`wordstat.yandex.ru`, а не на вызываемый хост `api.wordstat.yandex.net`); это
похоже на признак того, что старый API выведен из эксплуатации — официальная
документация Яндекса подтверждает переход на новый API через Yandex Cloud.
Пользователь решил реализовать оба варианта. План (Task 10, Task 12, Task 14)
переписан под два клиента (`WordstatLegacyClient`, `WordstatCloudClient`) за
одним интерфейсом `WordstatProvider` с переключателем в настройках. Токен
пользователя использован только для одного разового `curl`-запроса в этом
сеансе и нигде не сохранён в файлах.

Open risks: реальная форма ответа старого API не подтверждена (запрос не дошёл
до тела ответа) — `WordstatLegacyClient` использует парсер нового API как
предположение, это явно помечено в плане и коде как негарантированное;
изменение модели данных `SemanticKeyword`/`Topic` и SwiftData-миграция (Tasks
4–5); квоты нового Yandex Cloud API не подтверждены официальным источником.

Next agent should check: прогресс по задачам 2–15 плана (Task-инструмент этой
сессии отслеживает статус); после завершения всех задач — предложить
`superpowers:finishing-a-development-branch`.
