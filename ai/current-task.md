# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: intake

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

review

## Goal

Живой сбор семантики в установленном приложении падает почти сразу с
`WordstatResponseParser.ParserError error 0` (badResponse) — Wordstat вернул
ответ, который не удалось разобрать как ожидаемый JSON. Нужно найти корневую
причину (сам ответ Wordstat, устаревший/сломанный ключ, лимиты, изменившийся
формат API) и исправить парсинг или причину плохого ответа.

Замечание: сам новый механизм resume/остановки сработал правильно — прогон
корректно остановился на первой ошибке, сохранил прогресс (1 из 1664) и
предложил «Продолжить сбор». Это НЕ регрессия resume-фичи.

## Use Superpowers

yes

## Relevant files

SEOContentCreator/SEOContentCreator/Logic/WordstatResponseParser.swift
SEOContentCreator/SEOContentCreator/Logic/WordstatCloudClient.swift
SEOContentCreator/SEOContentCreator/Logic/WordstatLegacyClient.swift
SEOContentCreator/SEOContentCreator/Logic/WordstatCredentialStore.swift

## Done criteria

- Найдена корневая причина ParserError на реальном запросе к Wordstat.
- Сбор семантики на реальной теме проходит от кнопки до сохранённого
  результата без ParserError (либо ошибка теперь описывает настоящую причину,
  если проблема на стороне Wordstat/аккаунта, а не в парсере).

## Agent handoff

Last agent: Claude Code, 2026-07-23

What changed:

- Корневая причина найдена и подтверждена живым запросом к реальному Cloud
  API (curl, с ключом/folderId из Keychain пользователя, тот же payload, что
  и в приложении): для фразы `"мрт"` API вернул валидный `results: [...]`, но
  для заведомо бессмысленной фразы без данных — `HTTP 200` с телом `{}`,
  без поля `results` вообще (не `"results": []`).
- `WordstatResponseParser`/`Response.results` был обязательным полем без
  дефолта, поэтому отсутствие ключа декодировалось как `DecodingError`,
  превращалось в `ParserError.badResponse` — то есть частый штатный случай
  «у фразы нет данных» ошибочно считался поломкой ответа.
- Это критично взаимодействовало с сегодняшним же изменением
  (`SemanticCollectionRunner` теперь останавливает весь прогон на первой
  ошибке Wordstat) — почти любой реальный прогон с тысячами seed-фраз
  падал на первой же фразе без данных.
- Исправлено: `Response` теперь декодирует `results` через
  `decodeIfPresent(...) ?? []`. Добавлен тест
  `treatsEmptyObjectAsNoPhrases()` в `WordstatResponseParserTests.swift`,
  воспроизводящий именно тело `{}`. Все тесты парсера (5 шт.) и
  соответствующие тесты раннера прошли.
- Собрана и установлена Release-сборка в `/Applications`; старая копия
  сохранена как бэкап. База данных (7 тем) на месте.

Open risks:

- Пользователь ещё не подтвердил живой повторный прогон после фикса —
  у него уже есть сохранённый чекпоинт (1 из 1664), «Продолжить сбор»
  должен повторить именно ту фразу, на которой всё упало, и на этот раз
  получить пустой (не ошибочный) результат.

Next agent should check:

1. Дождаться подтверждения пользователя, что «Продолжить сбор» проходит
   дальше второй фразы и в итоге завершается (или падает на чём-то новом —
   тогда разбирать отдельно).
2. Если всё ок — предложить `task-finish`.
