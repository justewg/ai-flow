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
- `[APP-07]` Добавлен единый snapshot состояния автоматики: `scripts/codex/status_snapshot.sh` + команда `scripts/codex/run.sh status_snapshot` (daemon/watchdog/executor/queues/blockers/rate-limit/backlog-seed).
- `[APP-07]` Добавлен ops-сервис `scripts/codex/ops_bot_service.js`: web dashboard (`/ops/status`), JSON status (`/ops/status.json`) и Telegram webhook-команды (`/status`, `/summary`, `/help`, `/status_page`).
- `[APP-07]` Добавлена PM2-обвязка ops-сервиса (`ops_bot_pm2_*`) и runbook интеграции с nginx/webhook: `docs/ops-bot-dashboard.md`.
- `[APP-07]` Добавлен скрипт регистрации Telegram webhook из env: `scripts/codex/ops_bot_webhook_register.sh` + команда `scripts/codex/run.sh ops_bot_webhook_register [register|info]`.
- `[APP-07]` Добавлен безопасный refresh webhook без ручной подстановки токена: `scripts/codex/ops_bot_webhook_refresh.sh` и команда `scripts/codex/run.sh ops_bot_webhook_refresh` (делает `deleteWebhook + setWebhook + getWebhookInfo` из env).
- `[APP-07]` Добавлен split-runtime bridge для статуса автоматики: серверный ingest endpoint `POST /ops/ingest/status` в `ops_bot_service.js` + локальный push-скрипт `scripts/codex/ops_remote_status_push.sh` (daemon-loop отправляет snapshot по тикам на удаленный ops-bot).
- `[PL-017]` Добавлен preview-деплой до merge: GitHub workflow `.github/workflows/deploy-dev-pr.yml` (trigger на `pull_request -> main`) с выкладкой в `DEPLOY_DEV_PATH` через тот же rsync/ssh-пайплайн, что и прод.
- `[PL-017]` Расширен dev-деплой workflow `.github/workflows/deploy-dev-pr.yml`: добавлен авто-триггер на `push` в `development`, чтобы `planka-dev` обновлялся сразу после пуша в ветку разработки.
- `[APP-07]` Добавлен helper-скрипт `scripts/codex/issue_285_reframe_apply.sh` и команда `scripts/codex/run.sh issue_285_reframe_apply` для автоматического рефрейма `Issue #285` в manual-only rollout, split задач на automation/post-smoke и проставления label `auto:ignore` для ручной задачи.

### Fixed
- `[APP-07]` Исправлен fallback split-runtime статуса: при `local=UNKNOWN` `/ops/status(.json)` теперь использует последний `remote_ingest` snapshot даже если он stale (с полями `remote_stale`/`remote_age_sec`), чтобы статус не обнулялся при rate-limit backoff `daemon_loop`; также увеличен default `OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC` до `600`.
- `[APP-07]` Улучшен UI `/ops/status`: значения `detail` в блоках `Daemon/Watchdog` теперь разбиваются переносами после `;`, а моно-блоки получили фиксированную высоту с вертикальным скроллом (`overflow-y:auto`) без расширения карточек.
- `[APP-07]` Устранен разрыв remote-status bridge для старого рантайма daemon: `daemon_tick` теперь выполняет `ops_remote_status_push` на `EXIT` (даже без рестарта `daemon_loop`), а `daemon_loop` передает флаг `DAEMON_LOOP_PUSH_REMOTE=1`, чтобы после рестарта избежать двойной отправки snapshot.
- `[APP-07]` Исправлены ложные hourly Telegram-алерты `GITHUB_RUNTIME_WAIT`: `daemon_loop` больше не шлет runtime-сигнал при `WAIT_GITHUB_RATE_LIMIT`, если runtime-очередь пуста; текст wait-алерта разделен на кейсы `GitHub недоступен` и `GitHub GraphQL rate limit`.
- `[APP-07]` Устранены ложные watchdog hard-restart в `WAIT_GITHUB_RATE_LIMIT`: `watchdog_tick` теперь использует увеличенный stale-порог для `daemon.log` в rate-limit режиме (по умолчанию от `DAEMON_RATE_LIMIT_MAX_SLEEP_SEC`), поэтому легальный backoff-сон демона не считается зависанием.
- `[APP-07]` В `daemon_loop.sh` добавлен экспоненциальный backoff при `WAIT_GITHUB_RATE_LIMIT`: интервал следующего тика растет `90 -> 180 -> 360` сек (с насыщением на `360`), после успешного тика backoff сбрасывается к базовому интервалу.
- `[APP-07]` Добавлен ignore-label фильтр auto-claim в `daemon_tick` (`AUTO_IGNORE_LABELS`, по умолчанию `auto:ignore`): задачи с этим label не берутся из `Todo`, а если label поставлен на уже активную задачу — daemon освобождает active-context и останавливает executor.
- `[APP-07]` Исправлен приоритет dirty-gate относительно ignore-label: `find_first_todo_issue_json` теперь учитывает `AUTO_IGNORE_LABELS`, поэтому `Todo`-задачи с `auto:ignore` не инициируют `DIRTY-GATE` при dirty worktree.
- `[APP-07]` Усилен auto-release активной задачи в `daemon_tick`: статус активной карточки теперь читается по прямому `ProjectV2Item id` (без лимита первых 100 items), а при ручном переводе задачи из `In Progress` (например, в `Backlog`) daemon сбрасывает `daemon_active_*`, останавливает executor и очищает waiting/review-контекст этой же задачи, чтобы не блокировать подхват следующей.
- `[APP-07]` Dependency-gate в `daemon_tick` больше не блокирует задачу на битых зависимостях: несуществующие `Depends-On` issue теперь игнорируются (`DEPENDENCY_MISSING_IGNORED`), а неразбираемые dependency-токены логируются как `DEPENDENCY_TOKEN_IGNORED_UNRESOLVED` и не останавливают claim.
- `[APP-07]` Усилен `backlog_seed_apply`: при `GitHub API rate limit` теперь явно эмитятся `WAIT_GITHUB_RATE_LIMIT`/`..._STAGE`/`..._MSG` (а при сетевой деградации — `WAIT_GITHUB_API_UNSTABLE`), чтобы daemon переходил в корректное wait-состояние вместо тихого `...WARN` в `IDLE`.
- `[ISSUE-233]` Переформатированы dirty-worktree Telegram-оповещения в `scripts/codex/daemon_loop.sh`: заголовки приведены к `PLANKA: ...`, добавлены структурированные строки `Reason/State/Blocked/Tracked/Action/Time`, чтобы алерты оставались читаемыми и при plain-показе.
- `[APP-05]` Исправлено логирование auth-ошибок в `daemon_loop.sh` и `watchdog_loop.sh`: корректный `AUTH_RC` сохраняется в `WAIT_AUTH_SERVICE` (раньше в части кейсов логировался `rc=0`).
- `[APP-07]` Добавлена поддержка `DAEMON_GH_PROJECT_TOKEN`/`CODEX_GH_PROJECT_TOKEN` в project-скриптах и `daemon_tick`, чтобы daemon мог работать с user-owned Project v2 при App token для `Issue/PR`.
- `[APP-07]` Добавлены Telegram-алерты блокировки `WAIT_DIRTY_WORKTREE` (enter/changed/reminder/resolved), чтобы блокер tracked-изменений был виден без просмотра логов.
- `[APP-07]` `daemon_tick` теперь пишет детали dirty-worktree (`WAIT_DIRTY_WORKTREE_TRACKED_COUNT`, `WAIT_DIRTY_WORKTREE_TRACKED_FILES`) для state/detail и уведомлений.
- `[APP-07]` Исправлен dirty-gate reply flow: `COMMIT/STASH/REVERT/IGNORE` теперь распознаются как `REWORK`-ответы blocker, а карточка dirty-gate issue переводится в `In Progress` при обработке ответа.
- `[APP-07]` Для команды `COMMIT` в dirty-gate добавлен временный override (аналогично `IGNORE`), чтобы daemon не зацикливался в `WAIT_DIRTY_WORKTREE` после `AGENT_RESUMED`.
- `[APP-07]` Добавлен реальный auto-`COMMIT` в dirty-gate: daemon при ответе `COMMIT` делает commit+push tracked-изменений через `dev_commit_push.sh` (на `development`) и только после успеха продолжает flow.
- `[APP-07]` Устранен `ERROR_LOCAL_FLOW` при dirty-override: daemon пропускает `sync_branches` (`checkout main`) в режиме `WAIT_DIRTY_WORKTREE_OVERRIDE_ACTIVE=1`.
- `[APP-07]` Доработан `COMMIT` в dirty-gate до полного цикла: commit/push -> PR `development -> main` -> merge PR -> перевод dirty-gate в Done и закрытие issue, после чего daemon возвращается к штатному подхвату Todo.
- `[APP-07]` Добавлен auto-release stale active-state: если карточку активной задачи вручную уводят из `In Progress` (например, обратно в `Todo`), daemon сбрасывает локальный `daemon_active_*` и снова клеймит очередь.
- `[APP-07]` Убрано влияние служебных `DIRTY-GATE` issue на обычный claim: daemon исключает их из основной/fallback очереди `Todo`, чтобы они не блокировали подхват рабочих задач.
- `[APP-07]` Dirty-worktree Telegram-алерты теперь отправляются только при реальном блоке задачи из `Todo`; в idle (нет `Todo`) уведомления о dirty-state не отправляются.
- `[APP-07]` Устранено ложное ожидание `WAIT_USER_REPLY` в idle: daemon не восстанавливает stale waiting-контекст `DIRTY-GATE`, если нет текущей блокируемой карточки в `Todo`.
- `[APP-07]` Устранено дублирование dirty-gate сообщений при создании issue: остается один подробный блокер-текст (в теле issue), без дополнительного краткого комментария в тот же тик.
- `[APP-07]` При создании/линковке dirty-gate issue ее карточка в Project сразу переводится в `Status/Flow=In Progress` (вместо зависания в `Todo`).
- `[APP-07]` Добавлен runtime backlog-seed apply (`scripts/codex/backlog_seed_apply.sh`): daemon по тикам пытается создавать задачи из `.tmp/codex/backlog_seed_plan.json`, при частичном успехе автоматически удаляет созданные из плана и удаляет план при полном завершении.
- `[APP-07]` Исправлен dependency-gate: `Depends-On` теперь считается выполненным не только при `Issue=CLOSED`, но и при `Project Status=Done/Closed` у зависимой карточки.
- `[APP-07]` Усилен парсинг `Depends-On`: daemon корректно обрабатывает склеенный формат `#162#163` (без запятой), разбивает его на отдельные зависимости и устраняет ложный блок `WAIT_DEPENDENCIES`.
- `[APP-07]` Усилены правила для executor по оформлению PR: обязательная детализация фактических изменений, затронутых файлов, проверок и scope; fallback `task_finalize` теперь генерирует более информативный PR body со списком stage-paths.
- `[APP-07]` Добавлен recovery якоря review-комментария в `task_finalize`: если `AGENT_IN_REVIEW` не вернул `comment_id` и outbox не активирован, скрипт автоматически ставит recovery-комментарий в GitHub outbox (`REVIEW_FEEDBACK`, `set_waiting=1`), чтобы ссылка на PR не терялась.
- `[APP-07]` Исправлен перевод `DIRTY-GATE` в `In Progress`: при создании/линковке gate-issue daemon использует уже полученный `project item id` для `project_set_status`, чтобы исключить race-condition (`Task not found in project: ISSUE-xxx`) в тот же тик.
- `[APP-07]` Добавлен fallback от залипания `WAIT_REVIEW_FEEDBACK`: если связанный review PR уже `MERGED` или `CLOSED`, `daemon_check_replies` автоматически очищает waiting/review-контекст и не блокирует очередь даже при сбое `Project Auto Close Tasks`.
- `[APP-07]` Исправлен `project_set_status` для больших Project v2: добавлена пагинация `items` (по `endCursor/hasNextPage`), чтобы `ISSUE-xxx`/`Task ID` находились за пределом первых 100 карточек и не возникал ложный `Task not found in project`.
- `[APP-07]` Добавлена runtime-очередь отложенных `Project Status/Flow` апдейтов: `scripts/codex/project_status_runtime.sh` + команда `run.sh project_status_runtime`, чтобы при недоступном GitHub status-intent не терялся и автоматически доезжал после восстановления API.
- `[APP-07]` `daemon_tick` и `executor_tick` теперь на каждом тике применяют runtime-очередь status-апдейтов; `task_finalize`, review-resume, claim и backlog-seed при сетевой деградации переводят status-операции в deferred-runtime вместо silent-drop/жесткого стопа.
- `[APP-07]` В `daemon_loop` добавлены отдельные Telegram-сигналы доступности GitHub для runtime-очереди (`GITHUB_RUNTIME_WAIT` / `GITHUB_RUNTIME_RECOVERED`) и подавление дублирующих generic-degraded алертов для чисто GitHub-деградации.
- `[APP-07]` Добавлен CLI-отчет `scripts/codex/log_summary.sh` (и `run.sh log_summary`) для суммаризации логов daemon/watchdog/runtime/graphql за период: доступность GitHub, длительность деградаций, heartbeat, rate-limit окна и состояние runtime-очереди.
- `[APP-07]` Доработан `log_summary`: запуск без аргументов теперь строит отчет по всему доступному диапазону логов, GitHub-деградации считаются также по `GITHUB_STATUS` в `STATE ... DETAIL`, чтение идет со snapshot логов (без залипания на активно дописываемом `daemon.log`).
- `[APP-07]` `log_summary` расширен по “тишине автоматики”: добавлены метрики и длительности не-GitHub ожиданий (`WAIT_DIRTY_WORKTREE`, `WAIT_USER_REPLY`, `WAIT_REVIEW_FEEDBACK`, `WAIT_DEPENDENCIES`), `IDLE_NO_TASKS` и `daemon_state_age` в `Current State`.
- `[APP-07]` Исправлено залипание active-task при dirty-worktree: `daemon_tick` теперь не обрывает тик до `executor_tick`, если есть активный/ожидающий контекст (`daemon_active_task`/`waiting`/`review`), но по-прежнему блокирует claim новых задач (`WAIT_DIRTY_WORKTREE_SKIP_NEW_CLAIM=1`) до очистки tracked-изменений или override.
