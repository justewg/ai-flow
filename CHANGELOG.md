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
- `[PL-015]` В prototype/web заменен текстовый portrait-fallback на визуальную мнемонику поворота (иконка), без текстовых предупреждений.
- `[PL-014]` Добавлен и закреплен в тулбаре toggle светлой/темной темы с сохранением выбора между перезапусками.
- `[PL-003]` Усилен web-прототип 50/50: добавлены shell-бар, стабильный split-layout и fallback-экран для portrait.
- `[PL-003]` Добавлены попытка фиксации landscape, сохранение/восстановление состояния (`localStorage`) и обновленная документация `prototype/web/README.md`.
- `[PL-003]` Перекомпонован тулбар: убрана служебная надпись, кнопки темы/языка/очистки перенесены в верхнюю правую зону, высота поля ввода увеличена за счет удаления промежуточного toolbar.
- `[PL-004]` Уплотнена клавиатурная сетка для мобильного viewport: уменьшены внутренние отступы/промежутки, символы центрированы в кнопках, нижний ряд пересобран под `Пробел(8)` + `Backspace(4)`.
- `[PL-016]` Добавлена клавиша Enter (`↵`) как последняя кнопка третьего ряда: вставляет перевод строки (`\n`) и поддерживается также клавишей Enter на аппаратной клавиатуре.
- `[PL-017]` Включен автодеплой `main` на hosting по `GitHub Actions + rsync/ssh`, добавлен manual fallback-скрипт и инструкция настройки секретов.
- `[PL-018]` Добавлен верхний цифровой ряд `1..0` над буквенными кнопками в клавиатуре прототипа.
- `[PL-019]` Добавлен workflow автозакрытия задач по merged PR: `PL-xxx` из title/body автоматически переводятся в `Done` в GitHub Project (`Status` и `Flow`).
- `[PL-019]` Устранена нестабильность `unknown owner type` в Actions: перевод карточек в `Done` переведен на GraphQL (`updateProjectV2ItemFieldValue`) с fail-fast поведением workflow.
- `[PL-019]` Исправлен лимит GitHub GraphQL для project items: `itemsFirst` уменьшен до `100`, чтобы workflow автозакрытия не падал с `first limit of 100`.
- `[PL-020]` Проведен успешный smoke-тест автозакрытия: после merge PR задачи `PL-019` и `PL-020` автоматически переведены в `Done`.
- `[PL-021]` Добавлены Telegram push-уведомления из GitHub Actions через `TG_BOT_TOKEN` и `TG_CHAT_ID`.
- `[PL-022]` Добавлены Telegram-сигналы на события PR-ревью и финальные статусы post-merge workflow (`Deploy Main to Hosting`, `Project Auto Close Tasks`).
- `[APP-07]` Добавлен детальный runbook `APP-07.5` в `docs/gh-app-daemon-integration-plan.md`: выдача доступа GitHub App к Project v2, обновление installation и верификация через App token.
- `[APP-07]` Добавлен onboarding-checklist включения auth-сервиса GitHub App в `docs/gh-app-daemon-integration-plan.md` (env, pm2, launchd, деградация/recovery).
- `[APP-07]` Обновлен `README.md`: добавлена ссылка на runbook/онбординг GitHub App auth-сервиса.
- `[APP-07]` Обновлен `scripts/codex/README.md`: добавлены указания по Project v2 permissions для App и быстрый health-check включения сервиса.
- `[APP-07]` Созданы smoke-артефакты проверки авторства через App token: `Issue #142` и `PR #143`.
- `[APP-07]` Зафиксирован hybrid-режим для user-owned Project v2: App token для `Issue/PR`, отдельный `DAEMON_GH_PROJECT_TOKEN` для Project операций.
- `[APP-07]` В `docs/gh-app-daemon-integration-plan.md` добавлена инструкция, где выпускать PAT для `DAEMON_GH_PROJECT_TOKEN` и как проверять доступы.

### Fixed
- `[APP-05]` Исправлено логирование auth-ошибок в `daemon_loop.sh` и `watchdog_loop.sh`: корректный `AUTH_RC` сохраняется в `WAIT_AUTH_SERVICE` (раньше в части кейсов логировался `rc=0`).
- `[APP-07]` Добавлена поддержка `DAEMON_GH_PROJECT_TOKEN`/`CODEX_GH_PROJECT_TOKEN` в project-скриптах и `daemon_tick`, чтобы daemon мог работать с user-owned Project v2 при App token для `Issue/PR`.
