# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: spec

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Сделать этап «Семантика» автоматическим или полуавтоматическим. ИИ-агент формирует
списки запросов (маски, синонимы, минус-слова) для выгрузки из Yandex Wordstat по
бесплатному API, приложение подтягивает запросы с частотностью, затем агент чистит
и оценивает список по методике сбора семантического ядра.

Сейчас реального сбора нет: `SemanticMockKeywordCollector` клеит шаблоны вида
«тема + лечение», а `SemanticAgentAnalyzer` оценивает эти выдуманные кандидаты без
частотности.

Стадия spec: идёт brainstorming, дизайн ещё не утверждён.

## Use Superpowers

yes

## Relevant files

- `SEOContentCreator/SEOContentCreator/Logic/SemanticMockKeywordCollector.swift`
- `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentAnalyzer.swift`
- `SEOContentCreator/SEOContentCreator/Logic/SemanticAgentResponseParser.swift`
- `SEOContentCreator/SEOContentCreator/Logic/SemanticKeywordMerger.swift`
- `SEOContentCreator/SEOContentCreator/Logic/SemanticPromptRenderer.swift`
- `SEOContentCreator/SEOContentCreator/Models/SemanticKeyword.swift`
- `SEOContentCreator/SEOContentCreator/Views/SemanticAgentSheet.swift`
- `docs/superpowers/specs/2026-07-02-semantic-agent-design.md` — предыдущий дизайн этапа
- `docs/superpowers/specs/` — сюда ляжет новый дизайн-документ

## Done criteria

- Утверждён и закоммичен дизайн-документ по автоматизации этапа «Семантика».
- Остальные критерии уточняются в ходе brainstorming.

## Agent handoff

Last agent: Claude Opus 4.8

What changed: выполнен `task-switch` — задача про интент читателя ушла в
`ai/paused-tasks.md` (дизайн и план готовы, реализация не начата). Записана новая
задача, идёт brainstorming.

Open risks: внешний API Yandex Wordstat (авторизация, лимиты, стоимость и объём
выгрузки); изменение модели данных `SemanticKeyword` и SwiftData-миграция; расход
токенов на больших списках запросов; пересечение с приостановленной задачей про
интент читателя — обе трогают то, как семантика попадает на этап «Структура».

Next agent should check: результат brainstorming и новый дизайн-документ в
`docs/superpowers/specs/`.
