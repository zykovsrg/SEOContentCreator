# Decisions

Важные активные архитектурные, продуктовые, workflow-решения и решения по модели данных.

Не используй этот файл для мелких багфиксов, косметических правок или обычной истории изменений.

## Шаблон

### YYYY-MM-DD — Название решения

Status: active / superseded / resolved

Decision:

Why:

Impact:

## Текущие решения

### 2026-05-21 — Стек приложения: нативный SwiftUI

Status: active

Decision:

Приложение реализуется как нативное macOS-приложение на SwiftUI. Веб-обёртка (Tauri/Electron) отклонена.

Why:

Нужен только macOS — кроссплатформенность веб-обёртки не требуется. Один цельный стек (Swift + SwiftUI) проще вести не-разработчику с ИИ-сопровождением и надёжнее, чем связка «веб-фронт + упаковщик». Нативный вид и ощущение, хорошая поддержка ИИ. Целевые экраны (side-by-side, дерево Базы знаний, списки, формы) хорошо ложатся на SwiftUI.

Impact:

Skill frontend-design (веб-ориентированный) напрямую не применяется — UI проектируется через brainstorming + макеты и реализуется в SwiftUI. Потребуется Xcode и разовая настройка подписи приложения. Следующий шаг — фронтенд-дизайн ключевых экранов.

### 2026-05-21 — Продуктовая архитектура нового приложения (Вариант B)

Status: active

Decision:

Принят Вариант B (смелое переосмысление) для редизайна приложения. Ключевое: единая лента версий вместо слотов; side-by-side как основной экран; короткий видимый пайплайн (8 обязательных + 2 опциональных этапа), технические этапы скрыты в контекст ИИ-ролей; ИИ-роли (автор, SEO, фактчекер, редактор) с независимой проверкой; База знаний клиники (древовидный справочник); структурированный бриф (направление/врач из Базы знаний) вместо тегов; Google Docs только как точка публикации без обратной синхронизации; ручная правка сквозная.

Why:

Главная боль старого приложения — слишком много видимых этапов и непрозрачность артефактов. Вариант B убирает это, сохраняя полезную суть. Single-user снимает переходный барьер.

Impact:

Полная спека — `docs/superpowers/specs/2026-05-19-content-system-redesign-design.md`. Перед реализацией нужно выбрать стек (нативный macOS / веб). Отложено: автоимпорт из Docs, аналитика конкурентов.

### 2026-05-17 — Plan files are source of truth for plan-driven progress

Status: active

Decision:

For Superpowers or other plan-driven workflows, `docs/superpowers/plans/<plan>.md` is the source of truth for execution progress. Agents must update plan checkboxes after each completed plan task, add short `Note:` entries for local judgment calls, and use `Plan Task <N>: <short action>` commit messages for plan-driven commits.

Why:

Internal TodoWrite state is session-local and disappears when switching agents or chats. Keeping progress in the plan file and using a simple commit convention makes handoff verifiable without extra tools.

Impact:

Ordinary non-plan-driven tasks are unchanged. `ai/decisions.md` remains for durable decisions, `ai/changelog.md` remains for notable summaries, and plan notes are used only for local decisions inside a specific plan.
