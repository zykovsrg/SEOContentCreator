# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: implementation

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation

## Goal

Сделать длительный сбор семантики наблюдаемым и управляемым: показывать текущий этап, прогресс и время, поддержать остановку пользователем и общий таймаут без частичного изменения семантики.

## Use Superpowers

yes

## Relevant files

SEOContentCreator/SEOContentCreator/Logic/SemanticCollectionRunner.swift
SEOContentCreator/SEOContentCreator/Views/SemanticFunnelView.swift
SEOContentCreator/SEOContentCreatorTests/SemanticCollectionRunnerTests.swift

## Done criteria

- Во время сбора видны текущий этап, прогресс Wordstat и прошедшее время.
- Пользователь может остановить сбор; закрытие окна также отменяет активную работу.
- Через 10 минут сбор автоматически прекращается с понятным сообщением.
- Отмена и таймаут не изменяют сохранённую семантику.
- Поведение покрыто профильными автоматическими тестами и ручным UI-чек-листом.

## Agent handoff

Last agent:

What changed:

Open risks:

Next agent should check:
