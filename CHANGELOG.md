# CHANGELOG.md
Все существенные изменения проекта фиксируются здесь.

Формат: `task-id` + краткое описание результата.
Правило: в `CHANGELOG.md` попадают только фактически завершенные изменения.

## [Unreleased]

### Added
- `[PL-000]` Добавлены артефакты управления разработкой: `TODO.md` и `CHANGELOG.md`.
- `[PL-000]` Зафиксировано правило синхронизации: задача считается завершенной только после отражения результата в changelog.
- `[PL-013]` Создан GitHub Project `PLANKA Roadmap`: `https://github.com/users/justewg/projects/2`.
- `[PL-013]` Добавлены поля `Task ID`, `Priority`, `Scope`, `Flow` и импортирован backlog `PL-001..PL-012` как draft items.
- `[PL-001]` Подготовлен первый продуктовый артефакт: `docs/aba-curator-presentation-v1.md`.
- `[PL-001]` Сформирована структура презентации для ABA-куратора с вопросами на обратную связь и критериями пилота.
- `[PL-002]` Зафиксирован архитектурный выбор для MVP: `WebView + Native Shell` с обязательным fallback в `Native Android` по gate-критериям.
- `[PL-002]` Добавлена матрица валидации и протокол прогонов: `docs/pl-002-validation-matrix.md`.
- `[PL-001]` Добавлена графичная презентация v2: `presentations/aba-v2/index.html` + `presentations/aba-v2/mermaid/*.mmd`.
