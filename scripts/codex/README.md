# scripts/codex

Стабильные wrapper-команды для снижения confirm-шума в Codex VSCode.

## Рекомендуемый вход (один префикс)
- `scripts/codex/run.sh <command>`

Для полного онбординга GitHub App auth-сервиса см.:
- `docs/gh-app-daemon-integration-plan.md` (разделы `Runbook: APP-07.5` и `Онбординг сервиса`).

Команды:
- `scripts/codex/run.sh help`
- `scripts/codex/run.sh clear <key>`
- `scripts/codex/run.sh write <key> <value...>`
- `scripts/codex/run.sh append <key> <value...>`
- `scripts/codex/run.sh copy <key> <source-file>`
- `scripts/codex/run.sh sync_branches`
- `scripts/codex/run.sh pr_list_open`
- `scripts/codex/run.sh pr_view`
- `scripts/codex/run.sh pr_create`
- `scripts/codex/run.sh pr_edit`
- `scripts/codex/run.sh commit_push`
- `scripts/codex/run.sh project_add_task`
- `scripts/codex/run.sh project_set_status`
- `scripts/codex/run.sh next_task` — показать следующую задачу со статусом `Planned` (приоритет P0→P1→P2, затем по номеру `PL-xxx`).
- `scripts/codex/run.sh app_deps_mermaid [output-file]` — построить Mermaid DAG зависимостей APP-issues из `Flow Meta` (`Depends-On/Blocks`) и записать markdown-файл (по умолчанию `docs/app-issues-dependency-diagram.md`).
- `scripts/codex/run.sh daemon_tick` — один цикл демона: проверка `Todo`, подхват задачи, перевод в `In Progress`.
- `scripts/codex/run.sh daemon_loop [interval-sec]` — непрерывный polling-цикл демона (по умолчанию 45 сек).
- `scripts/codex/run.sh daemon_install [label] [interval-sec]` — установка и запуск `launchd`-агента.
- `scripts/codex/run.sh daemon_uninstall [label]` — остановка и удаление `launchd`-агента.
- `scripts/codex/run.sh daemon_status [label]` — проверка статуса `launchd`-агента.
- `scripts/codex/run.sh watchdog_tick` — один цикл самодиагностики/самовосстановления.
- `scripts/codex/run.sh watchdog_loop [interval-sec]` — непрерывный watchdog-цикл.
- `scripts/codex/run.sh watchdog_install [label] [interval-sec]` — установка и запуск `launchd`-watchdog.
- `scripts/codex/run.sh watchdog_uninstall [label]` — остановка и удаление `launchd`-watchdog.
- `scripts/codex/run.sh watchdog_status [label]` — проверка статуса watchdog.
- `scripts/codex/run.sh executor_reset` — сброс состояния автономного executor.
- `scripts/codex/run.sh executor_start <task-id> <issue-number>` — запуск автономного executor.
- `scripts/codex/run.sh executor_tick <task-id> <issue-number>` — проверка/перезапуск executor, обработка fail-state.
- `scripts/codex/run.sh executor_build_prompt <task-id> <issue-number> <output-file>` — сбор prompt для executor из Issue.
- `scripts/codex/run.sh task_ask <question|blocker> <message-file>` — отправить вопрос/блокер в comment Issue и включить режим ожидания ответа.
- `scripts/codex/run.sh daemon_check_replies` — проверить ответы в Issue-комментах для ожидающего вопроса.
- `scripts/codex/run.sh task_finalize` — финализация задачи: commit+push, create/update PR, перевод задачи в `Status=Review`, `Flow=In Review`.
- `scripts/codex/run.sh gh_retry <command> [args...]` — выполнить GitHub-команду с retry/backoff.
- `scripts/codex/run.sh github_health_check` — быстрый preflight GitHub API (`healthy/unstable`).
- `scripts/codex/run.sh github_outbox <enqueue_issue_comment|flush|count|list> ...` — управление отложенными GitHub-действиями.
- `scripts/codex/run.sh gh_app_auth_start` — запустить локальный GitHub App auth-сервис (`/health`, `/token`).
- `scripts/codex/run.sh gh_app_auth_health` — проверить endpoint `/health` auth-сервиса.
- `scripts/codex/run.sh gh_app_auth_probe` — проверить `/health` и `/token` (без вывода токена).
- `scripts/codex/run.sh gh_app_auth_pm2_start` — зарегистрировать/перезапустить auth-сервис в PM2.
- `scripts/codex/run.sh gh_app_auth_pm2_stop` — остановить и удалить auth-сервис из PM2.
- `scripts/codex/run.sh gh_app_auth_pm2_restart` — перезапустить auth-сервис в PM2.
- `scripts/codex/run.sh gh_app_auth_pm2_status` — показать статус auth-сервиса в PM2.
- `scripts/codex/run.sh gh_app_auth_pm2_health` — проверить PM2 status=`online` + endpoint `/health`.
- `scripts/codex/run.sh gh_app_auth_pm2_crash_test` — kill процесса auth-сервиса и подтвердить авто-restart PM2.

`run.sh` читает фиксированные файлы из `.tmp/codex/`:
- `pr_number.txt`
- `pr_title.txt`
- `pr_body.txt`
- `commit_message.txt`
- `stage_paths.txt`
- `project_task_id.txt`
- `project_status.txt`
- `project_flow.txt` (опционально)
- `project_new_task_id.txt`
- `project_new_title.txt`
- `project_new_scope.txt`
- `project_new_priority.txt`
- `project_new_status.txt` (опционально)
- `project_new_flow.txt` (опционально)

Ключи для `clear/write/append/copy`:
- `pr_number`, `pr_title`, `pr_body`
- `commit_message`, `stage_paths`
- `project_task_id`, `project_status`, `project_flow`
- `project_new_task_id`, `project_new_title`, `project_new_scope`, `project_new_priority`, `project_new_status`, `project_new_flow`

Поведение `write`/`append`:
- Поддерживаются escape-последовательности, например `\n` для многострочного текста.
- Если нужен буквальный `\n`, передавайте `\\n`.

## Рекомендация по снижению confirm-окон
- Не использовать `&&`, `;`, heredoc и цепочки команд для подготовки данных.
- Делать отдельные вызовы `scripts/codex/run.sh write/append/clear`.
- Затем отдельно вызывать `scripts/codex/run.sh <action>`.

## Важные env-переменные
- `node` (Node.js runtime, рекомендуется LTS >= 18) — обязателен для `gh_app_auth_*` скриптов и сервиса `gh_app_auth_service.js`.
- `GH_APP_INTERNAL_SECRET` — обязателен не только для auth-сервиса, но и для daemon/watchdog-клиента токена (`GET /token`).
- Для корректной работы `daemon_tick` с Project v2 у GitHub App должен быть доступ `Projects: Read and write` на уровне `Account permissions` (user-owned project) или `Organization permissions` (org-owned project).
  - Если в daemon-логе есть `Resource not accessible by integration`, сначала проверить permissions App и обновить installation (`Configure`), затем повторить smoke.
- Для user-owned Project v2 рекомендуется hybrid mode:
  - `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) используется только для Project-операций (`item-list`, `Status/Flow` update, claim из `Todo`);
  - `Issue/PR` продолжают работать на App token из auth-сервиса.
- `DAEMON_GH_AUTH_TIMEOUT_SEC` — timeout запроса daemon/watchdog к локальному auth endpoint (по умолчанию `8` сек).
- `DAEMON_GH_AUTH_TOKEN_URL` — опциональный явный URL `GET /token` (по умолчанию `http://${GH_APP_BIND:-127.0.0.1}:${GH_APP_PORT:-8787}/token`).
- `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) — отдельный PAT для Project v2 операций.
  - Где получить: `GitHub -> Settings -> Developer settings -> Personal access tokens`.
  - Рекомендуемый тип: `Tokens (classic)` для user-owned Project API.
  - Минимальные scopes: `repo`, `read:project`, `project`.
  - После изменения значения перезапустить `daemon` и `watchdog`.
- `DAEMON_GH_TOKEN_FALLBACK_ENABLED` (или `CODEX_GH_TOKEN_FALLBACK_ENABLED`) — feature flag аварийного fallback на PAT.
  - По умолчанию `0` (fallback выключен).
  - Truthy-значения: `1`, `true`, `yes`, `on`.
  - При `1` и недоступном auth endpoint daemon/watchdog берут токен из `DAEMON_GH_TOKEN`/`CODEX_GH_TOKEN`.
  - При auth-деградации в `state/detail` пишется явная причина (`AUTH_DEGRADED=1`, `AUTH_FALLBACK_*`), daemon отправляет Telegram-сигнал.
- `DAEMON_GH_TOKEN` (или `CODEX_GH_TOKEN`) — отдельный GitHub token для daemon/watchdog.
  - Применяется ко всем действиям автоматики только в режиме fallback (`DAEMON_GH_TOKEN_FALLBACK_ENABLED=1`).
  - Автор этих действий в GitHub будет владельцем этого токена.
  - Читается из env процесса или из `.env`/`.env.deploy`.
  - Роль в архитектуре:
    - штатный режим: токен из локального GitHub App auth-сервиса;
    - PAT — только аварийный fallback (включается отдельно, не базовый путь).
  - Когда можно не задавать:
    - в штатном режиме GitHub App, если fallback не нужен.
  - Как выпустить:
    - GitHub UI -> `Settings` -> `Developer settings` -> `Personal access tokens`.
    - Рекомендуемо: токен отдельного bot-аккаунта (не личный), чтобы авторство действий было отделено.
    - Тип токена: `Tokens (classic)` (для простого старта) или fine-grained PAT с эквивалентными правами.
    - Минимальные права для текущего flow: `repo`, `read:project`, `project`.
    - После выпуска записать в `.env` и перезапустить сервисы.
  - После изменения значения перезапусти сервисы:
    - `scripts/codex/run.sh daemon_uninstall && scripts/codex/run.sh daemon_install`
    - `scripts/codex/run.sh watchdog_uninstall && scripts/codex/run.sh watchdog_install`
- `CODEX_GIT_AUTHOR_*` / `CODEX_GIT_COMMITTER_*` — отдельная identity только для git-коммитов агента.
- `GH_APP_ID`, `GH_APP_INSTALLATION_ID`, `GH_APP_PRIVATE_KEY_PATH`, `GH_APP_INTERNAL_SECRET` — обязательные переменные для auth-сервиса GitHub App.
- `GH_APP_BIND` / `GH_APP_PORT` — bind/port auth-сервиса (bind фиксируется как `127.0.0.1`).
- `GH_APP_TOKEN_SKEW_SEC` — упреждающее обновление installation token (по умолчанию `300` сек).
- `GH_APP_API_BASE_URL` — базовый URL GitHub API (по умолчанию `https://api.github.com`).
- `GH_APP_HTTP_TIMEOUT_MS` — timeout HTTP-запроса к GitHub API (по умолчанию `10000` мс).
- `GH_APP_PM2_APP_NAME` — имя PM2 процесса auth-сервиса (по умолчанию `planka-gh-app-auth`).
- `GH_APP_PM2_RESTART_TIMEOUT_SEC` — timeout проверки авто-restart в `gh_app_auth_pm2_crash_test` (по умолчанию `20` сек).

## Итеративный executor-flow (коммит1 -> вопрос -> ответ -> коммит2 -> финализация)
1. Сделать первую рабочую дельту и выполнить `commit_push`.
2. Если нужно подтверждение/уточнение, подготовить файл с вопросом и вызвать `scripts/codex/run.sh task_ask question <message-file>`.
3. После ответа пользователя продолжить реализацию второй дельты.
4. На финальном шаге заполнить `.tmp/codex/commit_message.txt` и `.tmp/codex/stage_paths.txt`, при необходимости обновить `pr_title`/`pr_body`, затем вызвать `scripts/codex/run.sh task_finalize`.
5. Если PR остался draft, перевести его в `ready_for_review`.

## Команды
- `dev_commit_push.sh "message" <path...>`
  - `git add` + `git commit` + `git push origin development`
  - для agent-коммитов использует отдельную identity (env): `CODEX_GIT_AUTHOR_NAME`, `CODEX_GIT_AUTHOR_EMAIL`, `CODEX_GIT_COMMITTER_NAME`, `CODEX_GIT_COMMITTER_EMAIL`
- `sync_branches.sh`
  - `fetch/pull/merge/push` для выравнивания `main` и `development` после merge PR
  - если `main` уже включен в `development`, merge пропускается
  - при merge-конфликте возвращает `BRANCH_SYNC_CONFLICT=1` (код 78)
- `pr_list_open.sh`
  - список открытых PR `development -> main`
- `pr_view.sh <pr-number>`
  - просмотр PR в фиксированном JSON-формате
- `pr_create.sh <title-file> <body-file>`
  - создание PR `development -> main`
- `pr_edit.sh <pr-number> <title-file> <body-file>`
  - обновление title/body PR
- `project_set_status.sh <task-id|project-item-id> <status-name> [flow-name]`
  - синхронное обновление полей `Status` и `Flow` карточки проекта
- `project_add_task.sh <task-id> <title-file> <scope> <priority> [status] [flow]`
  - создание карточки задачи в проекте с заполнением `Task ID`, `Scope`, `Priority`, `Status`, `Flow`
  - после создания делает verify `Status/Flow`; при сетевой деградации возвращает ошибку, чтобы не считать задачу корректно инициализированной
- `next_task.sh`
  - выводит `NEXT_TASK_ID=...` и `NEXT_TITLE=...` для ближайшей задачи (статус `Planned`)
- `generate_app_dependencies_mermaid.sh [output-file]`
  - читает APP-issues через GitHub API и парсит `Flow Meta -> Depends-On/Blocks`
  - строит Mermaid DAG в markdown (по умолчанию `docs/app-issues-dependency-diagram.md`)
  - ошибки парсинга отдельных токенов не прерывают генерацию, а добавляются в раздел `Ошибки парсинга`
- `daemon_tick.sh`
  - останавливается только при изменениях tracked-файлов (staged/unstaged)
  - при блокировке на tracked-изменениях пишет явные маркеры:
    - `WAIT_DIRTY_WORKTREE_TRACKED_COUNT=<n>`
    - `WAIT_DIRTY_WORKTREE_TRACKED_FILES=<csv preview>`
  - для dirty-gate reply (`COMMIT`/`STASH`/`REVERT`/`IGNORE`) пишет `WAIT_DIRTY_WORKTREE_GATE_ACTION=...`
  - при рабочем ответе (`REWORK`) переводит карточку dirty-gate issue в `Status/Flow=In Progress`
  - `COMMIT` запускает auto-commit tracked-файлов через `dev_commit_push.sh`; при успехе включает override (`WAIT_DIRTY_WORKTREE_OVERRIDE_SET=1`)
  - auto-`COMMIT` выполняется только из ветки `development` (иначе пишет `WAIT_DIRTY_WORKTREE_COMMIT_BLOCKED_BRANCH=...`)
  - `IGNORE` включает временный override (`WAIT_DIRTY_WORKTREE_OVERRIDE_SET=1`) для текущей dirty-signature без коммита
  - при активном dirty-override пропускает `sync_branches` (`WAIT_BRANCH_SYNC_SKIPPED_DIRTY_OVERRIDE=1`), чтобы не падать на `checkout main`
  - untracked-файлы не блокируют daemon-flow
  - на старте тика делает `github_outbox flush` (доставка отложенных GitHub-комментариев)
  - перед взятием новой задачи проверяет waiting-state по Issue-комментариям (`daemon_check_replies.sh`)
  - при `WAIT_USER_REPLY`/`WAIT_REVIEW_FEEDBACK` не берет новые задачи
  - если в `In Review` пришел новый комментарий (`REVIEW_FEEDBACK`), автоматически переводит задачу обратно в `In Progress` и возобновляет executor
  - при наличии `daemon_active_task.txt` не берет новые задачи до финализации, но продолжает проверять ответы в Issue
  - для активной задачи вызывает `executor_tick.sh`, который запускает/мониторит headless executor (`codex exec`)
  - перед критичными GitHub-операциями делает preflight (`github_health_check.sh`)
  - сетевые вызовы к GitHub выполняет через `gh_retry.sh`, чтобы кратковременные DNS/API-сбои не роняли flow
  - если активной задачи нет, проверяет открытые PR `development -> main` и при наличии ждет merge/close
  - читает Project через GraphQL (без нестабильного `gh project item-list`)
  - в hybrid mode для Project-операций использует `DAEMON_GH_PROJECT_TOKEN`/`CODEX_GH_PROJECT_TOKEN` (если задан), сохраняя App token для `Issue/PR`
  - при исчерпании GraphQL rate limit пишет `WAIT_GITHUB_RATE_LIMIT=1` + детали (`..._STAGE`, `..._MSG`) и не берет новую задачу
  - ведет статистику окон между rate-limit событиями в `.tmp/codex/graphql_rate_stats.log` (`requests`, `duration_sec`, `start_utc`, `end_utc`)
  - берет задачу только из `Status=Todo`
  - перед подхватом читает `Flow Meta` у Issue и проверяет `Depends-On`
  - при незакрытых зависимостях не берет задачу, пишет `WAIT_DEPENDENCIES...` в вывод и отправляет одноразовый сигнал `CODEX_SIGNAL: AGENT_DEPENDENCY_BLOCKED` (через outbox при офлайне GitHub)
  - для автоподхвата учитывает только `Issue`; `DraftIssue` игнорируется
  - для перевода статуса использует `project item id`, поэтому не зависит от ручного заполнения поля `Task ID`
  - `Task ID` берет из поля, либо извлекает `PL-xxx` из title
  - если `PL-xxx` отсутствует, использует fallback `ISSUE-<number>` по номеру Issue
  - при единственной задаче переводит ее в `Status/Flow=In Progress`
  - сохраняет текущий `Task ID` в `.tmp/codex/project_task_id.txt` для последующего `task_finalize`
- `daemon_loop.sh [interval-sec]`
  - крутит `daemon_tick.sh` в цикле с lock-файлом и heartbeat-логом
  - перед каждым тиком получает свежий `GH_TOKEN` из локального auth endpoint (`/token`)
  - при ошибке auth-сервиса:
    - если включен `DAEMON_GH_TOKEN_FALLBACK_ENABLED` и доступен PAT (`DAEMON_GH_TOKEN`/`CODEX_GH_TOKEN`) — продолжает работу через fallback
    - иначе выставляет `WAIT_AUTH_SERVICE`
  - при auth-деградации пишет в detail явную причину (`AUTH_DEGRADED=1`, `AUTH_FALLBACK_*`) и отправляет Telegram-сигнал
  - пишет в `daemon_state_detail` явные health-маркеры: `GITHUB_STATUS=<...>` и `TELEGRAM_STATUS=<...>`
  - state `WAIT_GITHUB_RATE_LIMIT` трактуется как деградация `DEGRADED=GITHUB_GRAPHQL_RATE_LIMIT` и отправляет Telegram-алерт по тем же anti-spam правилам
  - state `WAIT_DIRTY_WORKTREE` отправляет отдельные Telegram-алерты блокировки:
    - вход (`WAIT_DIRTY_WORKTREE_ENTER`)
    - изменение набора файлов (`WAIT_DIRTY_WORKTREE_CHANGED`)
    - reminder (`WAIT_DIRTY_WORKTREE_REMINDER`)
    - снятие блокировки (`DIRTY_WORKTREE_RESOLVED`)
  - различает сетевую деградацию и веточный блокер синхронизации (`WAIT_BRANCH_SYNC`)
  - отправляет локальные Telegram-алерты по деградации без спама:
    - вход в деградацию (`ENTER_DEGRADED`)
    - смена причины деградации (`DEGRADED_CHANGED`)
    - периодический reminder (`DEGRADED_REMINDER`, по умолчанию раз в 30 минут)
    - восстановление (`RECOVERED`)
  - при DNS-проблемах GitHub дополнительно проверяет `api.telegram.org`
  - если Telegram доступен, отправляет приоритетный сигнал через бота о GitHub DNS-деградации (`GITHUB_DNS_TELEGRAM_OK_*`)
- `daemon_install.sh [label] [interval-sec]`
  - создает `~/Library/LaunchAgents/<label>.plist`
  - включает автозапуск демона при логине и restart при падении
- `daemon_uninstall.sh [label]`
  - выгружает и удаляет `launchd`-агент
- `daemon_status.sh [label]`
  - проверяет, запущен ли агент `launchd`
- `watchdog_tick.sh`
  - проверяет согласованность daemon/executor состояния
  - триггеры деградации:
    - `active_task` есть, но `executor_pid` мертв
    - `executor_state=RUNNING`, но heartbeat устарел
    - `daemon_state=IDLE_NO_TASKS`, но активная задача еще есть
    - stale `daemon.lock` + устаревший `daemon.log`
  - лестница восстановления:
    - `SOFT_DAEMON_TICK` (`daemon_tick`)
    - `MEDIUM_RESET_EXECUTOR` (`executor_reset` + `daemon_tick`)
    - `HARD_RESTART_DAEMON` (`daemon_uninstall` + `daemon_install`)
  - использует cooldown, чтобы не спамить recovery-действиями
  - отправляет Telegram-сигнал о срабатывании recovery (если доступен бот)
- `watchdog_loop.sh [interval-sec]`
  - крутит `watchdog_tick.sh` в цикле с отдельным lock-файлом
  - перед каждым циклом обновляет `GH_TOKEN` через локальный auth endpoint
  - при ошибке auth-сервиса использует тот же fallback-флаг `DAEMON_GH_TOKEN_FALLBACK_ENABLED`; без fallback выставляет `watchdog_state=WAIT_AUTH_SERVICE`
- `watchdog_install.sh [label] [interval-sec]`
  - создает `~/Library/LaunchAgents/<label>.plist` для watchdog
- `watchdog_uninstall.sh [label]`
  - выгружает и удаляет watchdog-агент
- `watchdog_status.sh [label]`
  - проверяет, запущен ли watchdog-агент
- `task_finalize.sh`
  - читает `commit_message.txt`, `stage_paths.txt`, `project_task_id.txt` (или `daemon_active_task.txt`)
  - выполняет commit/push в `development`
  - создает PR `development -> main` или обновляет существующий
  - переводит задачу в `Status=Review`, `Flow=In Review` (можно переопределить через `FINAL_STATUS` и `FINAL_FLOW`)
  - публикует `CODEX_SIGNAL: AGENT_IN_REVIEW` и включает waiting-контекст `REVIEW_FEEDBACK` для комментариев в Issue
  - очищает входные файлы commit/PR и активный daemon-state (active), сохраняя review-waiting контекст
- `executor_build_prompt.sh <task-id> <issue-number> <output-file>`
  - собирает prompt executor из текста Issue и последнего ответа пользователя
- `executor_start.sh <task-id> <issue-number>`
  - запускает `executor_run.sh` в фоне и сохраняет pid/state
- `executor_run.sh <task-id> <issue-number>`
  - выполняет `codex exec --full-auto` с подготовленным prompt
  - пишет результат в `.tmp/codex/executor.log` и обновляет state (`DONE/FAILED`)
  - обновляет heartbeat-файлы для диагностики "жив/завис"
- `executor_tick.sh <task-id> <issue-number>`
  - проверяет живость executor по pid/state
  - при `FAILED` автоматически публикует blocker-комментарий в Issue (один раз на задачу)
  - после нового ответа пользователя в Issue делает retry executor без ручного сброса state
  - при `DONE` и активной задаче без финализации публикует blocker-комментарий и ждет явного решения пользователя (`продолжай`/`финализируй`)
  - после нового ответа пользователя в этом состоянии запускает новый прогон executor
- `executor_reset.sh`
  - останавливает живой executor-процесс (если есть) и очищает state-файлы
- `task_ask.sh <question|blocker> <message-file>`
  - публикует структурированный комментарий в текущий Issue (`CODEX_SIGNAL: AGENT_QUESTION|AGENT_BLOCKER`)
  - при временной недоступности GitHub кладет комментарий в outbox и включает pending-waiting state
  - сохраняет waiting-state в `.tmp/codex/`, чтобы daemon ждал ответ пользователя
- `daemon_check_replies.sh`
  - если daemon в waiting-state, проверяет новые комментарии Issue после вопроса/ревью
  - для `AGENT_QUESTION/AGENT_BLOCKER` первый пользовательский комментарий (без `CODEX_SIGNAL:`) классифицирует как `QUESTION` или `REWORK`
    - `QUESTION` -> публикует `CODEX_SIGNAL: AGENT_ANSWER` и оставляет задачу в `WAIT_USER_REPLY`
    - `REWORK` -> публикует `CODEX_SIGNAL: AGENT_RESUMED` и передает задачу в работу
    - команды dirty-gate (`COMMIT`/`STASH`/`REVERT`/`IGNORE`) считаются `REWORK`
    - для явного продолжения после blocker используй `CODEX_MODE: REWORK`
  - для `REVIEW_FEEDBACK` принимает только не-системный комментарий автора Issue
  - для `REVIEW_FEEDBACK` различает режимы:
    - `QUESTION` -> публикует `CODEX_SIGNAL: AGENT_ANSWER` и оставляет задачу в `WAIT_REVIEW_FEEDBACK`
    - `REWORK` -> публикует `CODEX_SIGNAL: AGENT_RESUMED_REVIEW` и передает задачу в доработку
  - поддерживает явный override в комментарии: `CODEX_MODE: QUESTION|REWORK`
  - пишет явные маркеры review-feedback цикла: `WAIT_REVIEW_FEEDBACK`, `REVIEW_FEEDBACK_RECEIVED`, `REVIEW_FEEDBACK_RESUMED`
  - сохраняет ответ в `.tmp/codex/daemon_user_reply.txt`
  - публикует `CODEX_SIGNAL: AGENT_RESUMED`, `CODEX_SIGNAL: AGENT_RESUMED_REVIEW` или `CODEX_SIGNAL: AGENT_ANSWER`; если GitHub недоступен, кладет ответ/ack в outbox
  - при pending-question (`вопрос еще не доставлен`) удерживает `WAIT_USER_REPLY`, не теряя контекст
- `gh_retry.sh <command> [args...]`
  - retry/backoff для нестабильных ошибок GitHub API/DNS
  - на исчерпании попыток возвращает код `75` и `GITHUB_API_UNSTABLE=1`
- `github_health_check.sh`
  - preflight проверки GitHub API через `gh api rate_limit`
  - возвращает `GITHUB_HEALTHY=1` либо `GITHUB_API_UNSTABLE=1`
- `github_outbox.sh`
  - очередь отложенных GitHub-действий (сейчас: комментарии в Issue)
  - умеет `enqueue`, `flush`, `count`, `list`
  - при доставке queued question автоматически выставляет корректный waiting-state (`comment_id/url`)
  - пишет в лог структурированные сигналы отправки/ошибок (`GITHUB_ACTION_SENT`, `GITHUB_ACTION_SEND_FAILED`, `WAIT_GITHUB_PENDING_ACTIONS`)
- `gh_app_auth_service.js`
  - локальный Node.js auth-сервис для GitHub App
  - endpoint-ы: `GET /health`, `GET /token` (защищен `X-Internal-Secret`)
  - генерирует JWT, получает installation token, кэширует и обновляет его до истечения
- `gh_app_auth_start.sh`
  - запускает auth-сервис, предварительно загружая `.env` и `.env.deploy`
- `gh_app_auth_health.sh`
  - проверяет локальный `GET /health`
- `gh_app_auth_probe.sh`
  - проверяет `GET /health` и `GET /token`; валидирует ответ без вывода токена
- `gh_app_auth_pm2_ecosystem.config.cjs`
  - PM2 ecosystem-конфиг auth-сервиса (`autorestart`, отдельные log-файлы)
- `gh_app_auth_pm2_start.sh`
  - стартует auth-сервис под PM2 (или делает restart существующего процесса)
- `gh_app_auth_pm2_stop.sh`
  - останавливает и удаляет auth-сервис из PM2
- `gh_app_auth_pm2_restart.sh`
  - перезапускает auth-сервис в PM2
- `gh_app_auth_pm2_status.sh`
  - показывает состояние auth-сервиса в PM2 (`status`, `pid`, `restarts`, `uptime`)
- `gh_app_auth_pm2_health.sh`
  - проверяет, что PM2-процесс `online`, и валидирует `GET /health`
- `gh_app_auth_pm2_crash_test.sh`
  - имитирует падение процесса (`kill -9`) и подтверждает авто-restart PM2

Логи демона:
- `.tmp/codex/daemon.log` — heartbeat и результат `daemon_tick`
- `.tmp/codex/launchd.out.log` — stdout агента `launchd`
- `.tmp/codex/launchd.err.log` — stderr агента `launchd`
- `.tmp/codex/watchdog.log` — heartbeat watchdog и recovery-действия
- `.tmp/codex/watchdog_state.txt` — агрегированный статус watchdog
- `.tmp/codex/watchdog_state_detail.txt` — причина/деталь статуса watchdog
- `.tmp/codex/watchdog_last_action.txt` — последнее recovery-действие
- `.tmp/codex/watchdog_last_action_epoch.txt` — timestamp последнего recovery-действия
- `.tmp/codex/watchdog.launchd.out.log` — stdout watchdog-агента
- `.tmp/codex/watchdog.launchd.err.log` — stderr watchdog-агента
- `.tmp/codex/daemon_user_reply.txt` — последний ответ пользователя из Issue-комментариев
- `.tmp/codex/daemon_review_task_id.txt` — задача, ожидающая review-feedback
- `.tmp/codex/daemon_review_item_id.txt` — project item id задачи в review-feedback режиме
- `.tmp/codex/daemon_review_issue_number.txt` — issue number задачи в review-feedback режиме
- `.tmp/codex/daemon_review_pr_number.txt` — PR number для review-feedback режима
- `.tmp/codex/daemon_state.txt` — текущий агрегированный state демона (`IDLE_NO_TASKS`, `WAIT_OPEN_PR`, `WAIT_GITHUB_OFFLINE` и т.д.)
- `.tmp/codex/daemon_state_detail.txt` — краткая причина/деталь текущего state, включая признаки деградации (`DEGRADED=GITHUB_DNS_OFFLINE`, `DEGRADED=PENDING_OUTBOX:<n>` и т.п.)
- `.tmp/codex/daemon_notify_mode.txt` — последний режим уведомлений (`degraded|healthy`)
- `.tmp/codex/daemon_notify_last_epoch.txt` — timestamp последней попытки локального Telegram-уведомления
- `.tmp/codex/daemon_notify_last_signature.txt` — подпись последнего состояния, по которой определяется `DEGRADED_CHANGED`
- `.tmp/codex/graphql_rate_stats.log` — журнал rate-limit событий GraphQL (одно событие = окно от первого успешного запроса после лимита до нового лимита)
- `.tmp/codex/graphql_rate_window_state.txt` — состояние текущего окна (`WAIT_SUCCESS|RUNNING`)
- `.tmp/codex/graphql_rate_window_start_epoch.txt` — epoch старта текущего окна
- `.tmp/codex/graphql_rate_window_start_utc.txt` — UTC-старт текущего окна
- `.tmp/codex/graphql_rate_window_requests.txt` — число успешных GraphQL-запросов в текущем окне
- `.tmp/codex/graphql_rate_last_success_utc.txt` — время последнего успешного GraphQL-запроса
- `.tmp/codex/graphql_rate_last_limit_utc.txt` — время последнего зафиксированного rate-limit события
- `.tmp/codex/executor.log` — полный лог автономного executor
- `.tmp/codex/executor_state.txt` — состояние executor (`RUNNING|DONE|FAILED`)
- `.tmp/codex/executor_pid.txt` — pid фонового executor-процесса
- `.tmp/codex/executor_last_exit_code.txt` — код завершения последнего executor запуска
- `.tmp/codex/executor_heartbeat_utc.txt` — время последнего heartbeat executor
- `.tmp/codex/executor_heartbeat_epoch.txt` — epoch-время последнего heartbeat executor
- `.tmp/codex/outbox/` — pending GitHub-действия (очередь)
- `.tmp/codex/outbox_payloads/` — payload-файлы для pending действий
- `.tmp/codex/outbox_failed/` — non-retryable ошибки outbox

Быстрый анализ частоты GraphQL rate limit:
- последние события: `tail -n 20 .tmp/codex/graphql_rate_stats.log`
- среднее число успешных GraphQL-запросов до нового лимита:
  `awk -F'\t' '/EVENT=RATE_LIMIT/ { for(i=1;i<=NF;i++) if($i ~ /^requests=/){ split($i,a,"="); sum+=a[2]; n++ } } END { if(n) printf("avg_requests=%.2f events=%d\n", sum/n, n); else print "no_data" }' .tmp/codex/graphql_rate_stats.log`
- средняя длительность окна (сек):
  `awk -F'\t' '/EVENT=RATE_LIMIT/ { for(i=1;i<=NF;i++) if($i ~ /^duration_sec=/){ split($i,a,"="); sum+=a[2]; n++ } } END { if(n) printf("avg_duration_sec=%.2f events=%d\n", sum/n, n); else print "no_data" }' .tmp/codex/graphql_rate_stats.log`

Быстрая проверка включения App auth:
- `scripts/codex/run.sh gh_app_auth_pm2_health`
- `cat .tmp/codex/daemon_state.txt`
- `cat .tmp/codex/daemon_state_detail.txt`
- при необходимости: `tail -n 80 .tmp/codex/daemon.log`

## Подготовка
Скрипты должны быть исполняемыми:

```bash
chmod +x scripts/codex/*.sh
```

Опциональные переменные для локальных Telegram-алертов демона:
- `DAEMON_TG_BOT_TOKEN` (или `TG_BOT_TOKEN`)
- `DAEMON_TG_CHAT_ID` (или `TG_CHAT_ID`)
- `DAEMON_TG_ENV_FILE` (путь к env-файлу; по умолчанию проверяются `.env`, `.env.deploy`)
- `DAEMON_TG_REMINDER_SEC` (интервал reminder в секундах, минимум 60; по умолчанию 1800)
- `DAEMON_TG_GH_DNS_REMINDER_SEC` (интервал напоминаний именно для деградации `GITHUB_DNS_OFFLINE` при доступном Telegram; минимум 60, по умолчанию 300)
- `DAEMON_TG_DIRTY_REMINDER_SEC` (интервал reminder для блокировки `WAIT_DIRTY_WORKTREE`; минимум 60, по умолчанию 600)
- `DAEMON_GH_TOKEN_FALLBACK_ENABLED` (или `CODEX_GH_TOKEN_FALLBACK_ENABLED`) — включает аварийный fallback на `DAEMON_GH_TOKEN`/`CODEX_GH_TOKEN` при недоступном auth endpoint
- `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) — отдельный PAT для Project v2 в hybrid mode (если Project user-owned)
- `WATCHDOG_DAEMON_LABEL` (какой daemon label перезапускать при hard recovery; по умолчанию `com.planka.codex-daemon`)
- `WATCHDOG_DAEMON_INTERVAL_SEC` (интервал daemon после hard restart; по умолчанию 45)
- `WATCHDOG_COOLDOWN_SEC` (минимальная пауза между recovery-действиями; по умолчанию 120)
- `WATCHDOG_EXECUTOR_STALE_SEC` (порог stale heartbeat executor; по умолчанию 180)
- `WATCHDOG_DAEMON_LOG_STALE_SEC` (порог stale daemon log/lock; по умолчанию 180)
