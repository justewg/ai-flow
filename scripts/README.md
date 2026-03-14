# .flow/shared/scripts

Стабильные wrapper-команды для снижения confirm-шума в Codex VSCode.

> Канонический shared-toolkit path: `.flow/shared/{scripts,docs}`.
> Путь `.flow/shared/scripts/*` в этом файле является каноническим entrypoint-слоем toolkit.

## Рекомендуемый вход (один префикс)
- `.flow/shared/scripts/run.sh <command>`

Для полного онбординга GitHub App auth-сервиса см.:
- `.flow/shared/docs/flow-onboarding-checklist.md` (сверхкороткий чеклист внедрения flow в новый repo/локальную папку).
- `.flow/shared/docs/flow-onboarding-quickstart.md` (быстрый onboarding flow-комплекта в новый repo/локальную папку проекта).
- `.flow/shared/docs/flow-toolkit-packaging.md` (что переносить в другой проект и как выносить automation в отдельный toolkit-repo).
- `.flow/shared/docs/gh-app-daemon-integration-plan.md` (разделы `Runbook: APP-07.5` и `Онбординг сервиса`).
- `.flow/shared/docs/flow-portability-runbook.md` (миграция `current -> new project`, multi-project smoke, rollback, extraction strategy).
- `docs/self-hosted-runner-deploy.md` (перевод deploy workflow на self-hosted runner `planka-deploy`).

Команды:
- `.flow/shared/scripts/run.sh help`
- `.flow/shared/scripts/run.sh clear <key>`
- `.flow/shared/scripts/run.sh write <key> <value...>`
- `.flow/shared/scripts/run.sh append <key> <value...>`
- `.flow/shared/scripts/run.sh copy <key> <source-file>`
- `.flow/shared/scripts/run.sh dispatch [command]`
- `.flow/shared/scripts/run.sh issue_create`
- `.flow/shared/scripts/run.sh issue_view`
- `.flow/shared/scripts/run.sh issue_close`
- `.flow/shared/scripts/run.sh sync_branches`
- `.flow/shared/scripts/run.sh pr_list`
- `.flow/shared/scripts/run.sh pr_list_open`
- `.flow/shared/scripts/run.sh pr_view`
- `.flow/shared/scripts/run.sh pr_create`
- `.flow/shared/scripts/run.sh pr_edit`
- `.flow/shared/scripts/run.sh pr_merge`
- `.flow/shared/scripts/run.sh commit_push`
- `.flow/shared/scripts/run.sh git_ls_remote_heads`
- `.flow/shared/scripts/run.sh git_delete_branch`
- `.flow/shared/scripts/run.sh project_add_task`
- `.flow/shared/scripts/run.sh project_add_issue`
- `.flow/shared/scripts/run.sh project_set_status`
- `.flow/shared/scripts/run.sh log_tail_executor`
- `.flow/shared/scripts/run.sh log_tail_daemon_executor`
- `.flow/shared/scripts/run.sh log_tail_all`
- Для interactive approvals и переменных аргументов:
  - не вызывать `gh ...`, `git ...`, `project_set_status.sh ...` напрямую;
  - записывать входные данные в fixed input files через `run.sh write/copy/clear`;
  - записывать имя команды в `.flow/tmp/run/dispatch_command.txt`;
  - при необходимости записывать аргументы по одному в `.flow/tmp/run/dispatch_args.txt`;
  - выполнять один стабильный entrypoint: `.flow/shared/scripts/run.sh dispatch`.
  - создание временных файлов/директорий через `mktemp`, `.flow/tmp` или `/tmp` не считается отдельным approval-поводом; approval может понадобиться только для внешнего действия в той же команде (`gh`, сеть, запись вне sandbox и т.п.).
- `.flow/shared/scripts/run.sh project_status_runtime <enqueue|apply|list|clear> ...` — runtime-очередь отложенных обновлений `Project Status/Flow`.
- `.flow/shared/scripts/run.sh log_summary [--hours N|--from ISO|--to ISO]` — агрегированный отчет по логам daemon/watchdog/runtime/graphql за период (без аргументов берёт весь доступный диапазон логов).
- `.flow/shared/scripts/run.sh status_snapshot` — нормализованный JSON snapshot состояния автоматики (daemon/watchdog/executor/очереди/blockers).
- `.flow/shared/scripts/run.sh next_task` — показать следующую задачу со статусом `Planned` (приоритет P0→P1→P2, затем по номеру `PL-xxx`).
- `.flow/shared/scripts/run.sh app_deps_mermaid [output-file]` — построить Mermaid DAG зависимостей APP-issues из `Flow Meta` (`Depends-On/Blocks`) и записать markdown-файл (по умолчанию `docs/app-issues-dependency-diagram.md`).
- `.flow/shared/scripts/run.sh backlog_seed_apply` — применить runtime-план создания backlog-задач из `<state-dir>/backlog_seed_plan.json` (по умолчанию 1 задача за запуск).
- `.flow/shared/flow-init.sh [--profile <name>] [--target-repo <path>]` — канонический initializer launcher для нового или ещё не подключённого проекта. Его можно публиковать как raw-entrypoint и вызывать через `bash <(curl -fsSL ...)`. Launcher bootstrap-ит `/.flow/shared`, materialize-ит минимальный `.flow` layout, пишет безопасный `flow.sample.env`/`flow.env` через `profile_init init` и затем запускает `flow_configurator questionnaire` или печатает однозначный следующий шаг, если interactive tty недоступен.
- `.flow/shared/scripts/run.sh bootstrap_repo --profile <name> [--target-repo <path>]` — internal/bootstrap layer, который materialize-ит `.flow/shared` в target repo как submodule (или minimal git-clone fallback вне git worktree), создаёт `.flow/config`/`.flow/tmp/wizard`, кладёт стартовый `COMMAND_TEMPLATES.md` и вызывает `profile_init init`.
- `.flow/shared/scripts/run.sh onboarding_audit [--profile <name>] [--skip-network]` — первичный аудит consumer-project: toolkit-файлы, локальные команды, git/gh, project-scoped flow env, repo и Project v2, repo workflow overlay и наличие обязательных GitHub Actions secrets.
- `.flow/shared/scripts/run.sh update_toolkit [--ref <name>]` — подтянуть repo-local submodule `/.flow/shared` до `origin/<ref>` (по умолчанию `main`) и показать, изменился ли gitlink в родительском repo.
- `.flow/shared/scripts/run.sh create_migration_kit --project <name> [--defaults-from <current|sample>] [--include-secrets] [--source-profile <name>] [--keep-project-binding] --target-repo <path> [--output <path>]` — собрать payload-only `migration_kit.tgz` без toolkit: `.flow/config/flow.env`, `.flow/config/flow.sample.env`, `.flow/github/*`, `.flow/templates/github/*`; в target repo записать `.flow/migration/do_migration.sh`, `.flow/migration/migration.conf`, `.flow/migration/README.md` и локальную копию payload archive. По умолчанию migration kit очищает `GITHUB_REPO` и `PROJECT_*`; сохранить source binding можно только явным `--keep-project-binding`.
  Явные log-path overrides (`FLOW_LOGS_DIR`, `FLOW_RUNTIME_LOG_DIR`, `FLOW_PM2_LOG_DIR`) при этом автоматически переписываются на `<AI_FLOW_ROOT_DIR>/logs/<target-profile>[/runtime|/pm2]`.
- `.flow/migration/do_migration.sh` — launcher в target repo: bootstrap-ит `/.flow/shared` из `ai-flow` по repo/ref из `.flow/migration/migration.conf` и затем запускает toolkit `apply_migration_kit` с локальным payload archive.
- `.flow/shared/scripts/run.sh apply_migration_kit [--project <name>] [--migration-config <path>] [--payload-archive <path>]` — применить payload archive проекта: материализовать `.flow/config/flow.sample.env`, `.flow/config/flow.env`, сохранить `.flow/config/migration.conf`, развернуть `.flow/templates/github/*` и repo overlay `.github/*`.
- `.flow/shared/scripts/run.sh flow_configurator [questionnaire] --profile <name>` — интерактивный wizard для `.flow/config/flow.env`: задаёт вопросы по repo/project/token/auth/Telegram/launchd/ops/remotes, показывает defaults и preview diff, пишет файл только после явного confirm. Если repo уже настроен и `flow.env` существует, wizard подставляет текущие значения как defaults: non-secret поля можно просто подтверждать Enter, а секреты остаются sticky, пока их не заменить явно.
- `.flow/shared/scripts/run.sh profile_init <init|install|preflight|bootstrap|orchestrate> ...` — bootstrap и финальная orchestration нового profile/repo без ручной сборки install/smoke-команд. Канонический порядок для нового или уже существующего проекта: сначала `flow-init.sh` или `bootstrap_repo`, затем `flow_configurator questionnaire`, затем `onboarding_audit`, затем `profile_init orchestrate`.
- `.flow/shared/scripts/run.sh daemon_tick` — один цикл демона: проверка `Todo`, подхват задачи, перевод в `In Progress`.
- `.flow/shared/scripts/run.sh daemon_loop [interval-sec]` — непрерывный polling-цикл демона (по умолчанию 45 сек).
- `.flow/shared/scripts/run.sh daemon_install [label] [interval-sec]` — установка и запуск `launchd`-агента.
- `.flow/shared/scripts/run.sh daemon_uninstall [label]` — остановка и удаление `launchd`-агента.
- `.flow/shared/scripts/run.sh daemon_status [label]` — проверка статуса `launchd`-агента.
- `.flow/shared/scripts/run.sh watchdog_tick` — один цикл самодиагностики/самовосстановления.
- `.flow/shared/scripts/run.sh watchdog_loop [interval-sec]` — непрерывный watchdog-цикл.
- `.flow/shared/scripts/run.sh watchdog_install [label] [interval-sec]` — установка и запуск `launchd`-watchdog.
- `.flow/shared/scripts/run.sh watchdog_uninstall [label]` — остановка и удаление `launchd`-watchdog.
- `.flow/shared/scripts/run.sh watchdog_status [label]` — проверка статуса watchdog.
- `.flow/shared/scripts/run.sh executor_reset` — сброс состояния автономного executor.
- `.flow/shared/scripts/run.sh runtime_clear_active` — очистка active-context daemon (`daemon_active_*`).
- `.flow/shared/scripts/run.sh runtime_clear_waiting` — очистка waiting-context daemon (`daemon_waiting_*`).
- `.flow/shared/scripts/run.sh runtime_clear_review` — очистка review-context daemon (`daemon_review_*`).
- `.flow/shared/scripts/run.sh executor_start <task-id> <issue-number>` — запуск автономного executor.
- `.flow/shared/scripts/run.sh executor_tick <task-id> <issue-number>` — проверка/перезапуск executor, обработка fail-state.
- `.flow/shared/scripts/run.sh executor_build_prompt <task-id> <issue-number> <output-file>` — сбор prompt для executor из Issue.
- `.flow/shared/scripts/run.sh task_ask <question|blocker> <message-file>` — отправить вопрос/блокер в comment Issue и включить режим ожидания ответа.
- `.flow/shared/scripts/run.sh daemon_check_replies` — проверить ответы в Issue-комментах для ожидающего вопроса.
- `.flow/shared/scripts/run.sh task_finalize` — финализация задачи: commit+push, create/update PR, перевод задачи в `Status=Review`, `Flow=In Review`.
- `.flow/shared/scripts/run.sh gh_retry <command> [args...]` — выполнить GitHub-команду с retry/backoff.
- `.flow/shared/scripts/run.sh github_health_check` — быстрый preflight GitHub API (`healthy/unstable`).
- `.flow/shared/scripts/run.sh github_outbox <enqueue_issue_comment|flush|count|list> ...` — управление отложенными GitHub-действиями.
- `.flow/shared/scripts/run.sh gh_app_auth_start` — запустить локальный GitHub App auth-сервис (`/health`, `/token`).
- `.flow/shared/scripts/run.sh gh_app_auth_health` — проверить endpoint `/health` auth-сервиса.
- `.flow/shared/scripts/run.sh gh_app_auth_probe` — проверить `/health` и `/token` (без вывода токена).
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_start` — зарегистрировать/перезапустить auth-сервис в PM2.
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_stop` — остановить и удалить auth-сервис из PM2.
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_restart` — перезапустить auth-сервис в PM2.
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_status` — показать статус auth-сервиса в PM2.
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_health` — проверить PM2 status=`online` + endpoint `/health`.
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_crash_test` — kill процесса auth-сервиса и подтвердить авто-restart PM2.
- `.flow/shared/scripts/run.sh ops_bot_start` — запустить локальный ops-бот сервис (`/health`, `/ops/status`, `/ops/status.json`, Telegram webhook).
- `.flow/shared/scripts/run.sh ops_bot_health` — проверить endpoint `/health` ops-бота.
- `.flow/shared/scripts/run.sh ops_bot_pm2_start` — зарегистрировать/перезапустить ops-бот сервис в PM2.
- `.flow/shared/scripts/run.sh ops_bot_pm2_stop` — остановить и удалить ops-бот сервис из PM2.
- `.flow/shared/scripts/run.sh ops_bot_pm2_restart` — перезапустить ops-бот сервис в PM2.
- `.flow/shared/scripts/run.sh ops_bot_pm2_status` — показать статус ops-бот сервиса в PM2.
- `.flow/shared/scripts/run.sh ops_bot_pm2_health` — проверить PM2 status=`online` + endpoint `/health` ops-бота.
- `.flow/shared/scripts/run.sh ops_bot_post_smoke_check` — собрать агрегированный post-smoke отчет по rollout ops-бота.
- `.flow/shared/scripts/run.sh ops_bot_webhook_register [register|refresh|delete|info]` — управление Telegram webhook по env-переменным.
- `.flow/shared/scripts/run.sh ops_bot_webhook_refresh` — shortcut для полного refresh webhook (`deleteWebhook + setWebhook + getWebhookInfo`).
- `.flow/shared/scripts/run.sh ops_remote_status_push` — отправить текущий `status_snapshot` в удаленный ingest endpoint ops-бота (URL/secret берутся из env).
- `.flow/shared/scripts/run.sh ops_remote_summary_push` — отправить bundle `log_summary` (локальное окно `6h` по умолчанию) в удаленный ingest endpoint ops-бота.

## State-dir и multi-project
- Core flow state хранится в `<state-dir>`, где `<state-dir>=${CODEX_STATE_DIR:-${FLOW_STATE_DIR:-${ROOT_DIR}/.flow/state/codex/default}}`.
- Runtime и PM2 логи живут отдельно в `<log-dir>`; по умолчанию `<log-dir>=<sites-root>/.ai-flow/logs/<project>`.
- Override задаётся через `CODEX_STATE_DIR`; если он не задан, используется `FLOW_STATE_DIR`.
- По умолчанию используется `${ROOT_DIR}/.flow/state/codex/default`.
- Shared host-level flow root для общих логов по проектам: `${ROOT_DIR}/../.ai-flow`.
- Shared runtime root для логов по проектам можно держать через `${ROOT_DIR}/../.ai-flow`.
- Toolkit code для consumer-project должен жить в repo-local `/.flow/shared` (git submodule или snapshot copy).
- `.tmp/codex/` больше не является runtime-root; если каталог присутствует, это только compatibility-symlink layer к `.flow/`.
- Для параллельного запуска двух проектов на одном хосте задайте разные `<state-dir>`.
- Если используете `daemon_install`/`watchdog_install`, задайте ещё и разные `label`, чтобы не столкнулись launchd-агенты.

Матрица multi-profile env для двух проектов на одном хосте:

| Параметр | Current project (пример: PLANKA) | New project (пример: ACME) | Зачем нужен |
| --- | --- | --- | --- |
| `DAEMON_GH_ENV_FILE` | `<root-dir>/.flow/config/flow.env` | `<root-dir>/.flow/config/flow.env` | Привязывает daemon/watchdog к project-scoped flow env-файлу. |
| `CODEX_STATE_DIR` / `FLOW_STATE_DIR` | `<root-dir>/.flow/state/codex/planka` | `<root-dir>/.flow/state/codex/acme` | Разводит state, locks, runtime queue и фиксированные файлы `run.sh`. |
| `AI_FLOW_ROOT_DIR` | `<sites-root>/.ai-flow` | `<sites-root>/.ai-flow` или свой host-level root | Общий host-level namespace для shared логов и будущего общего flow-toolkit слоя. |
| `FLOW_LOGS_DIR` | `<sites-root>/.ai-flow/logs/planka` | `<sites-root>/.ai-flow/logs/acme` | Разводит runtime/PM2 логи по проектам и позволяет держать их вне repo. |
| `PROJECT_PROFILE` | `default` | `acme` | Включает отдельный project-binding; для non-default требуются все `PROJECT_*`. |
| `GITHUB_REPO` | `<owner>/<current-repo>` | `<owner>/<new-repo>` | Определяет repo для Issue/PR-команд и executor prompt. |
| `PROJECT_ID` / `PROJECT_NUMBER` / `PROJECT_OWNER` | binding текущего проекта или полный override | обязательный полный набор | Привязывает `daemon_tick`, `project_*`, `next_task` к конкретному Project v2. |
| `DAEMON_GH_PROJECT_TOKEN` | токен текущего Project | отдельный токен нового Project | Используется для Project v2 операций текущего flow. |
| `WATCHDOG_DAEMON_LABEL` | `com.flow.codex-daemon.current` | `com.flow.codex-daemon.acme` | Позволяет watchdog перезапускать только свой daemon. |
| launchd labels | `com.flow.codex-daemon.current` / `com.flow.codex-watchdog.current` | `com.flow.codex-daemon.acme` / `com.flow.codex-watchdog.acme` | Исключает конфликт plist и `launchctl`-процессов. |
| `FLOW_LAUNCHD_NAMESPACE` | `com.flow` | `com.flow` или свой namespace | Позволяет централизованно переопределить prefix labels без правки shell-скриптов. |

Bootstrap нового профиля:
1. В текущем проекте собрать переносимый kit:
   `.flow/shared/scripts/run.sh create_migration_kit --project acme --target-repo <HOME>/sites/acme-app`
   По умолчанию архив появится как `.flow/migration/acme-migration-kit.tgz`.
   Если нужен prefilled `flow.env` c текущими секретами:
   `.flow/shared/scripts/run.sh create_migration_kit --project acme --defaults-from current --include-secrets --target-repo <HOME>/sites/acme-app`
   Если target должен сохранить source binding для `GITHUB_REPO` и `PROJECT_*`, это нужно указать явно:
   `.flow/shared/scripts/run.sh create_migration_kit --project acme --defaults-from current --keep-project-binding --target-repo <HOME>/sites/acme-app`
2. В новом проекте перейти в `.flow/migration/`.
3. Выполнить:
   `./do_migration.sh`
   Он сам поднимет toolkit из `ai-flow`, передаст `migration.conf` и локальный payload archive в `apply_migration_kit`.
4. После `apply_migration_kit` должны появиться:
   - `.flow/config/flow.sample.env`
   - `.flow/config/flow.env`
   - `.flow/config/migration.conf`
   - `.flow/templates/github/required-files.txt`
   - `.flow/templates/github/required-secrets.txt`
   - `.github/workflows/*.yml` и, если был в source overlay, `.github/pull_request_template.md`
5. Если kit создавался без `--keep-project-binding`, в target `flow.env` поля `GITHUB_REPO` и `PROJECT_*` будут пустыми intentionally; их нужно заполнить через `flow_configurator questionnaire`.
6. `.flow/shared/scripts/run.sh onboarding_audit --profile acme` — проверить toolkit, docs, env и получить список недостающих настроек.
7. При необходимости дополнительно использовать:
   `.flow/shared/scripts/run.sh profile_init preflight --profile acme`
8. `.flow/config/flow.sample.env` использовать только как безопасный шаблон; канонический runtime-config хранить в `.flow/config/flow.env`.
9. Если kit собран без `--include-secrets`, repo Actions secrets и runtime secrets нужно создать вручную в GitHub UI нового repo по списку из `.flow/templates/github/required-secrets.txt`.
   Что именно вписывать в каждый secret: `.flow/shared/docs/github-actions-repo-secrets.md`.
10. После заполнения env:
   `.flow/shared/scripts/run.sh profile_init install --profile acme`
11. Для безопасной проверки команд без изменений использовать `--dry-run`.

Запуск и остановка профиля:
1. Первый запуск нового профиля: `.flow/shared/scripts/run.sh profile_init install --profile acme`
2. Проверка launchd-состояния: `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state .flow/shared/scripts/run.sh daemon_status com.flow.codex-daemon.acme`
3. Аналогично проверить watchdog: `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state .flow/shared/scripts/run.sh watchdog_status com.flow.codex-watchdog.acme`
4. Штатная остановка профиля: `.flow/shared/scripts/run.sh daemon_uninstall com.flow.codex-daemon.acme` и `.flow/shared/scripts/run.sh watchdog_uninstall com.flow.codex-watchdog.acme`
5. Повторный запуск после остановки: `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state .flow/shared/scripts/run.sh daemon_install com.flow.codex-daemon.acme 45`, затем `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state WATCHDOG_DAEMON_LABEL=com.flow.codex-daemon.acme WATCHDOG_DAEMON_INTERVAL_SEC=45 .flow/shared/scripts/run.sh watchdog_install com.flow.codex-watchdog.acme 45`

Smoke-check после bootstrap нового профиля:
1. `.flow/shared/scripts/run.sh profile_init preflight --profile acme` — ожидается `PREFLIGHT_READY=1`.
2. `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state .flow/shared/scripts/run.sh github_health_check`
3. `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state FLOW_STATE_DIR=.flow/state .flow/shared/scripts/run.sh status_snapshot`
4. `env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/shared/scripts/run.sh gh_app_auth_probe`
5. Для параллельной эксплуатации двух проектов повторить те же проверки для current profile и убедиться, что snapshot/log-файлы лежат в разных `<state-dir>`.

Rollback нового профиля:
1. Остановить новый профиль: `.flow/shared/scripts/run.sh watchdog_uninstall com.flow.codex-watchdog.acme` и `.flow/shared/scripts/run.sh daemon_uninstall com.flow.codex-daemon.acme`
2. Убедиться, что current profile продолжает работать в своём `<state-dir>` без изменений.
3. Если проблема в env/config, исправить `.flow/config/flow.env` и повторить `profile_init install --profile acme`.
4. Если откат полный, сохранить диагностические логи из `<state-dir>` нового профиля и только после этого удалить новый state-dir вручную.
5. Детальный сценарий миграции и troubleshooting см. в `.flow/shared/docs/flow-portability-runbook.md`.

Короткий rollout smoke-checklist для ops-бота:
1. `.flow/shared/scripts/run.sh ops_bot_pm2_start`
2. `.flow/shared/scripts/run.sh ops_bot_pm2_status` (ожидается `PM2_STATUS=online`)
3. `.flow/shared/scripts/run.sh ops_bot_pm2_health` (ожидается exit code `0` и JSON `status=ok`)
4. `.flow/shared/scripts/run.sh status_snapshot | jq .overall_status` и `.flow/shared/scripts/run.sh log_summary --hours 1` (без падений даже при частично отсутствующих `<state-dir>/*`)
5. `.flow/shared/scripts/run.sh ops_bot_webhook_register register` и `.flow/shared/scripts/run.sh ops_bot_webhook_register info`
6. Проверка Telegram-команд: `/status`, `/summary 6`, `/help`, `/status_page`

`run.sh` читает фиксированные файлы из `<state-dir>/`:
- `pr_number.txt`
- `pr_title.txt`
- `pr_body.txt`
- `commit_message.txt`
- `stage_paths.txt`
- `issue_number.txt`
- `issue_title.txt`
- `issue_body.txt`
- `issue_view_json.txt`
- `issue_view_jq.txt`
- `issue_close_reason.txt`
- `issue_close_comment.txt`
- `pr_state.txt`
- `pr_base.txt`
- `pr_head.txt`
- `pr_list_json.txt`
- `pr_list_jq.txt`
- `pr_merge_method.txt`
- `pr_delete_branch.txt`
- `git_remote.txt`
- `git_refs.txt`
- `branch_name.txt`
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
- `issue_number`, `issue_title`, `issue_body`, `issue_view_json`, `issue_view_jq`, `issue_close_reason`, `issue_close_comment`
- `pr_state`, `pr_base`, `pr_head`, `pr_list_json`, `pr_list_jq`, `pr_merge_method`, `pr_delete_branch`
- `git_remote`, `git_refs`, `branch_name`
- `project_task_id`, `project_status`, `project_flow`
- `project_new_task_id`, `project_new_title`, `project_new_scope`, `project_new_priority`, `project_new_status`, `project_new_flow`

Поведение `write`/`append`:
- Поддерживаются escape-последовательности, например `\n` для многострочного текста.
- Если нужен буквальный `\n`, передавайте `\\n`.

## Рекомендация по снижению confirm-окон
- Не использовать `&&`, `;`, heredoc и цепочки команд для подготовки данных.
- Делать отдельные вызовы `.flow/shared/scripts/run.sh write/append/clear`.
- Для `gh/git/project` действий из интерактивной сессии вызывать `.flow/shared/scripts/run.sh dispatch`.
- Для просмотра runtime-логов автоматики использовать `.flow/shared/scripts/run.sh log_tail_*`, а не прямые `/bin/bash -lc ... tail ...`.
- Для очистки служебного runtime-state использовать `.flow/shared/scripts/run.sh runtime_clear_*` и `.flow/shared/scripts/run.sh executor_reset`, а не прямые `truncate`.
- `dispatch_command.txt` должен содержать одно из fixed-input действий (`issue_create`, `issue_view`, `issue_close`, `pr_list`, `pr_view`, `pr_create`, `pr_edit`, `pr_merge`, `git_ls_remote_heads`, `git_delete_branch`, `project_add_issue`, `project_set_status`).

## Важные env-переменные
- `node` (Node.js runtime, рекомендуется LTS >= 18) — обязателен для `gh_app_auth_*`, `ops_bot_*` и сервисов `gh_app_auth_service.js`, `ops_bot_service.js`.
- `GH_APP_INTERNAL_SECRET` — обязателен не только для auth-сервиса, но и для daemon/watchdog-клиента токена (`GET /token`).
- Для корректной работы `daemon_tick` с Project v2 у GitHub App должен быть доступ `Projects: Read and write` на уровне `Account permissions` (user-owned project) или `Organization permissions` (org-owned project).
  - Если в daemon-логе есть `Resource not accessible by integration`, сначала проверить permissions App и обновить installation (`Configure`), затем повторить smoke.
- `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER` — binding текущего GitHub Project v2 для `daemon_tick`, `project_add_task.sh`, `project_set_status.sh`, `next_task.sh`.
  - Если binding явно не задан, helper-скрипты пытаются взять `PROJECT_NUMBER/PROJECT_OWNER` из env-файла профиля или из текущего repo-контекста.
  - Для переносимого flow задавайте все три переменные через env или env-файл, без редактирования исходников.
- `PROJECT_PROFILE` — имя профиля project-binding.
  - По умолчанию `default`.
  - Для любого non-default значения нужно явно задать `PROJECT_ID`, `PROJECT_NUMBER`, `PROJECT_OWNER`; при неполной конфигурации helper-скрипты и `daemon_tick` завершаются с явной ошибкой.
- В текущем flow `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) используется для Project v2 операций (`item-list`, `Status/Flow` update, claim из `Todo`).
- `Issue/PR` продолжают работать на App token из auth-сервиса.
- `DAEMON_GH_AUTH_TIMEOUT_SEC` — timeout запроса daemon/watchdog к локальному auth endpoint (по умолчанию `8` сек).
- `DAEMON_GH_AUTH_TOKEN_URL` — опциональный явный URL `GET /token` (по умолчанию `http://${GH_APP_BIND:-127.0.0.1}:${GH_APP_PORT:-8787}/token`).
- `DAEMON_RATE_LIMIT_BACKOFF_BASE_SEC` — базовый sleep daemon-loop при `WAIT_GITHUB_RATE_LIMIT` (по умолчанию равен `daemon_loop interval`).
- `DAEMON_RATE_LIMIT_MAX_SLEEP_SEC` — верхняя граница sleep daemon-loop при `WAIT_GITHUB_RATE_LIMIT` (по умолчанию `360` сек).
- `AUTO_IGNORE_LABELS` — CSV-список labels, которые исключают issue из auto-claim daemon (по умолчанию `auto:ignore`).
- `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) — отдельный PAT для Project v2 операций.
  - Где получить: `GitHub -> Settings -> Developer settings -> Personal access tokens`.
  - Рекомендуемый тип: `Tokens (classic)` для совместимости с текущим hybrid flow.
  - Минимальные scopes: `repo`, `read:project`, `project`.
  - Рекомендуемые дополнительные scopes: `read:org`, `read:discussions`.
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
    - После выпуска записать в `.flow/config/flow.env` и перезапустить сервисы.
  - После изменения значения перезапусти сервисы:
    - `.flow/shared/scripts/run.sh daemon_uninstall && .flow/shared/scripts/run.sh daemon_install`
    - `.flow/shared/scripts/run.sh watchdog_uninstall && .flow/shared/scripts/run.sh watchdog_install`
- `CODEX_GIT_AUTHOR_*` / `CODEX_GIT_COMMITTER_*` — отдельная identity только для git-коммитов агента.
- `GH_APP_ID`, `GH_APP_INSTALLATION_ID`, `GH_APP_PRIVATE_KEY_PATH`, `GH_APP_INTERNAL_SECRET` — обязательные переменные для auth-сервиса GitHub App.
- `GH_APP_BIND` / `GH_APP_PORT` — bind/port auth-сервиса (bind фиксируется как `127.0.0.1`).
- `GH_APP_TOKEN_SKEW_SEC` — упреждающее обновление installation token (по умолчанию `300` сек).
- `GH_APP_API_BASE_URL` — базовый URL GitHub API (по умолчанию `https://api.github.com`).
- `GH_APP_HTTP_TIMEOUT_MS` — timeout HTTP-запроса к GitHub API (по умолчанию `10000` мс).
- `GH_APP_PM2_APP_NAME` — имя PM2 процесса auth-сервиса (по умолчанию `planka-gh-app-auth`).
- `GH_APP_PM2_USE_DEFAULT` — если `1/true/yes/on`, `onboarding_audit` считает shared/default auth-service допустимым без отдельного `GH_APP_PM2_APP_NAME`, но только если явно заданы координаты сервиса через `DAEMON_GH_AUTH_TOKEN_URL` или `GH_APP_BIND/GH_APP_PORT`.
- `GH_APP_PM2_RESTART_TIMEOUT_SEC` — timeout проверки авто-restart в `gh_app_auth_pm2_crash_test` (по умолчанию `20` сек).
- `DAEMON_GH_ENV_FILE` — явный путь к project-scoped flow env-файлу; `profile_init install` прокидывает его в `launchd`-plist, чтобы daemon/watchdog переживали новый shell/login без ручного export.

## Итеративный executor-flow (коммит1 -> вопрос -> ответ -> коммит2 -> финализация)
1. Сделать первую рабочую дельту и выполнить `commit_push`.
2. Если нужно подтверждение/уточнение, подготовить файл с вопросом и вызвать `.flow/shared/scripts/run.sh task_ask question <message-file>`.
3. После ответа пользователя продолжить реализацию второй дельты.
4. На финальном шаге заполнить `<state-dir>/commit_message.txt` и `<state-dir>/stage_paths.txt`, при необходимости обновить `pr_title`/`pr_body`, затем вызвать `.flow/shared/scripts/run.sh task_finalize`.
5. Если PR остался draft, перевести его в `ready_for_review`.

## Команды
- `dev_commit_push.sh "message" <path...>`
  - `git add` + `git commit` + `git push origin <current-branch>`
  - `task_finalize` при необходимости вызывает его с явным override для task-ветки, а финальный PR все равно остается `development -> main`
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
  - fast-path для `PVTI_*`: не загружает `items(first:100)`/пагинацию, обновляет поля сразу по переданному `project item id`
- `project_status_runtime.sh <enqueue|apply|list|clear> ...`
  - runtime-очередь действий `project_set_status` в `<state-dir>/project_status_runtime_queue.json`
  - при деградации GitHub (`network/rate-limit`) сохраняет intent и не теряет изменение
  - `apply` по тикам аккуратно подчищает очередь при восстановлении GitHub API
- `log_summary.sh [--hours N|--from ISO|--to ISO]`
  - строит сводный отчет за период по:
    - heartbeat/state daemon
    - не-GitHub ожиданиям daemon (`WAIT_DIRTY_WORKTREE`, `WAIT_USER_REPLY`, `WAIT_REVIEW_FEEDBACK`, `WAIT_DEPENDENCIES`) с оценкой длительности
    - runtime-очереди (`enqueued/applied/wait/pending`)
    - GitHub деградации (state-based, `GITHUB_STATUS`-based и TG runtime transitions)
    - GraphQL rate-limit окнам (`graphql_rate_stats.log`)
    - watchdog heartbeat/recovery markers
  - читает snapshot логов на старте, чтобы отчет не зависал на “живом” `daemon.log`
  - в блоке `Current State` показывает оценку текущей длительности состояния (`daemon_state_age`)
- `project_add_task.sh <task-id> <title-file> <scope> <priority> [status] [flow]`
  - создание карточки задачи в проекте с заполнением `Task ID`, `Scope`, `Priority`, `Status`, `Flow`
  - после создания делает verify `Status/Flow`; при сетевой деградации возвращает ошибку, чтобы не считать задачу корректно инициализированной
- `.flow/shared/scripts/run.sh project_add_issue`
  - добавляет существующий GitHub Issue в Project v2 как issue-backed item через `gh project item-add --url ...`
  - использует fixed-input `issue_number.txt`, чтобы не плодить новые approval-подтверждения на плавающих `gh project item-add ... --url ...`
  - после добавления сразу синхронно выставляет `Status/Flow`, по умолчанию `Backlog/Backlog`
  - на время линковки временно ставит label `auto:ignore`, чтобы daemon не успел заклеймить карточку из дефолтного `Todo` до перевода в нужный `Status/Flow`
  - после успешной синхронизации `Status/Flow` снимает временно добавленный `auto:ignore`
  - игнорирует остаточные `project_new_status.txt` и `project_new_flow.txt`, чтобы новая issue-backed карточка всегда создавалась как `Backlog/Backlog`
  - если после добавления нужен другой `Status/Flow`, это делается отдельным вызовом `.flow/shared/scripts/run.sh project_set_status`
- `.flow/shared/scripts/run.sh issue_close`
  - закрывает существующий GitHub Issue через fixed-input `issue_number.txt`
  - опционально использует `issue_close_reason.txt` и `issue_close_comment.txt`
  - нужен для no-noise закрытия невалидных smoke/task issue без прямого `gh issue close ...`
- `.flow/shared/scripts/run.sh log_tail_executor`
  - печатает хвост `executor.log` из runtime log dir
- `.flow/shared/scripts/run.sh log_tail_daemon_executor`
  - печатает стандартный двойной хвост `daemon.log + executor.log`
- `.flow/shared/scripts/run.sh log_tail_all`
  - печатает стандартный хвост `daemon.log + watchdog.log + executor.log`
- `.flow/shared/scripts/run.sh runtime_clear_active`
  - очищает active runtime-context daemon без прямых `truncate`
- `.flow/shared/scripts/run.sh runtime_clear_waiting`
  - очищает waiting-context daemon без прямых `truncate`
- `.flow/shared/scripts/run.sh runtime_clear_review`
  - очищает review-context daemon без прямых `truncate`
- `next_task.sh`
  - выводит `NEXT_TASK_ID=...` и `NEXT_TITLE=...` для ближайшей задачи (статус `Planned`)
- `generate_app_dependencies_mermaid.sh [output-file]`
  - читает APP-issues через GitHub API и парсит `Flow Meta -> Depends-On/Blocks`
  - строит Mermaid DAG в markdown (по умолчанию `docs/app-issues-dependency-diagram.md`)
  - ошибки парсинга отдельных токенов не прерывают генерацию, а добавляются в раздел `Ошибки парсинга`
- `daemon_tick.sh`
  - в начале каждого тика пытается применить runtime backlog-seed план (`<state-dir>/backlog_seed_plan.json`) через `backlog_seed_apply.sh`
  - в стандартной конфигурации создает/линкует не более 1 backlog-задачи за тик (`BACKLOG_SEED_MAX_PER_TICK=1`)
  - если GitHub API недоступен, оставляет план нетронутым и повторит попытку на следующем тике
  - при rate-limit во время backlog-seed теперь поднимает явные wait-маркеры (`WAIT_GITHUB_RATE_LIMIT` + `..._STAGE/..._MSG`), чтобы daemon переходил в деградированный режим и отправлял корректные сигналы
  - по мере успешного создания задач автоматически сокращает план; при пустом плане удаляет `<state-dir>/backlog_seed_plan.json` и `<state-dir>/backlog_seed_plan.md`
  - минимальный формат плана: JSON c корневым `tasks[]`, где каждая задача содержит `code`, `title`, `description`, опционально `plan_key`, `depends_on_codes[]`, `blocks_codes[]`
  - останавливается только при изменениях tracked-файлов (staged/unstaged)
  - при блокировке на tracked-изменениях пишет явные маркеры:
    - `WAIT_DIRTY_WORKTREE_TRACKED_COUNT=<n>`
    - `WAIT_DIRTY_WORKTREE_TRACKED_FILES=<csv preview>`
  - для dirty-gate reply (`COMMIT`/`STASH`/`REVERT`/`IGNORE`) пишет `WAIT_DIRTY_WORKTREE_GATE_ACTION=...`
  - при первичном создании dirty-gate issue использует один подробный текст (в теле issue) и не дублирует его отдельным кратким blocker-комментарием
  - при создании/линковке dirty-gate issue сразу переводит ее карточку в `Status/Flow=In Progress`
  - при рабочем ответе (`REWORK`) переводит карточку dirty-gate issue в `Status/Flow=In Progress`
  - при dirty-worktree больше не “глушит” обслуживание активного контекста: если есть `daemon_active_task`/waiting/review, тик продолжает `daemon_check_replies` и `executor_tick`; при этом новые claim остаются заблокированы (`WAIT_DIRTY_WORKTREE_SKIP_NEW_CLAIM=1`)
  - `COMMIT` запускает полный dirty-gate flow: auto-commit tracked-файлов (`dev_commit_push.sh`) -> PR `development -> main` -> merge PR -> закрытие dirty-gate issue
  - если финальный `project_set_status(Done)` для dirty-gate не прошел, daemon фиксирует pending-finalize и ретраит завершение автоматически на следующих тиках (без нового user-reply)
  - по успешному завершению пишет `WAIT_DIRTY_WORKTREE_COMMIT_FLOW_DONE=1` и снимает dirty-gate state
  - auto-`COMMIT` выполняется только из ветки `development` (иначе пишет `WAIT_DIRTY_WORKTREE_COMMIT_BLOCKED_BRANCH=...`)
  - `IGNORE` включает временный override (`WAIT_DIRTY_WORKTREE_OVERRIDE_SET=1`) для текущей dirty-signature без коммита
  - при активном dirty-override пропускает `sync_branches` (`WAIT_BRANCH_SYNC_SKIPPED_DIRTY_OVERRIDE=1`), чтобы не падать на `checkout main`
  - untracked-файлы не блокируют daemon-flow
  - на старте тика делает `github_outbox flush` (доставка отложенных GitHub-комментариев)
  - на старте тика делает `project_status_runtime apply` (подчистка отложенных status-апдейтов)
  - перед взятием новой задачи проверяет waiting-state по Issue-комментариям (`daemon_check_replies.sh`)
  - при `WAIT_USER_REPLY`/`WAIT_REVIEW_FEEDBACK` не берет новые задачи
  - если в `In Review` пришел новый комментарий (`REVIEW_FEEDBACK`), автоматически переводит задачу обратно в `In Progress` и возобновляет executor
    - если перевод `Status/Flow` временно недоступен, action откладывается в runtime-очередь и выполнение продолжается
  - при наличии `daemon_active_task.txt` не берет новые задачи до финализации, но продолжает проверять ответы в Issue
  - если активная задача вручную выведена из `In Progress` (например, возвращена в `Todo`/`Backlog`), автоматически сбрасывает stale active-state и снова включает обычный claim из очереди
  - для stale-release проверяет `Status` активной карточки по прямому `Project item id` (не зависит от лимита первых 100 items) и при release чистит связанный waiting/review-контекст этой же задачи
  - для активной задачи вызывает `executor_tick.sh`, который запускает/мониторит headless executor (`codex exec`)
  - перед критичными GitHub-операциями делает preflight (`github_health_check.sh`)
  - сетевые вызовы к GitHub выполняет через `gh_retry.sh`, чтобы кратковременные DNS/API-сбои не роняли flow
  - если активной задачи нет, проверяет открытые PR `development -> main` и при наличии ждет merge/close
  - не-Project проверки (`issues/labels/comments/open PR`) выполняет через REST (`gh api repos/...`); GraphQL оставлен для Project v2
  - читает Project через GraphQL (без нестабильного `gh project item-list`)
  - в hybrid mode для Project-операций использует `DAEMON_GH_PROJECT_TOKEN`/`CODEX_GH_PROJECT_TOKEN` (если задан), сохраняя App token для `Issue/PR`
  - при исчерпании GraphQL rate limit пишет `WAIT_GITHUB_RATE_LIMIT=1` + детали (`..._STAGE`, `..._MSG`) и не берет новую задачу
  - ведет статистику окон между rate-limit событиями в `<state-dir>/graphql_rate_stats.log` (`requests`, `duration_sec`, `start_utc`, `end_utc`)
  - берет задачу только из `Status=Todo`
  - issue с label из `AUTO_IGNORE_LABELS` (по умолчанию `auto:ignore`) исключаются из auto-claim очереди
  - `AUTO_IGNORE_LABELS` учитывается и в dirty-gate: такие `Todo`-задачи не считаются блокирующими для создания `DIRTY-GATE`
  - dirty-gate использует один скан `find_first_todo_issue_json` на тик (общий кэш между `maybe_process_dirty_gate_reply` и `maybe_handle_dirty_worktree_gate`)
  - если активная задача получает ignore-label, daemon освобождает active-context, останавливает executor и возвращается в idle-цикл
  - перед подхватом читает `Flow Meta` у Issue и проверяет `Depends-On`
  - зависимость из `Depends-On` считается выполненной, если `Issue` закрыт (`state=CLOSED`) или карточка зависимости в Project имеет `Status=Done/Closed`
  - результат проверки `Depends-On` кэшируется на TTL (`DEPENDENCY_ISSUE_RESOLVED_CACHE_TTL_SEC`, по умолчанию `180`), чтобы не дергать Project-статус на каждом тике
  - если в `Depends-On` указан несуществующий Issue (битая ссылка), зависимость игнорируется и не блокирует claim (`DEPENDENCY_MISSING_IGNORED`)
  - если токен в `Depends-On` не удается распарсить как Issue-ссылку, он игнорируется (`DEPENDENCY_TOKEN_IGNORED_UNRESOLVED`)
  - при незакрытых зависимостях не берет задачу, пишет `WAIT_DEPENDENCIES...` в вывод и отправляет одноразовый сигнал `CODEX_SIGNAL: AGENT_DEPENDENCY_BLOCKED` (через outbox при офлайне GitHub)
  - для автоподхвата учитывает только `Issue`; `DraftIssue` игнорируется
  - issue с заголовком `DIRTY-GATE:` исключаются из штатной claim-очереди (они служебные и обрабатываются только dirty-gate веткой)
  - stale waiting по `DIRTY-GATE` не восстанавливается, если сейчас нет реальной блокируемой карточки в `Todo` (исключает ложный `WAIT_USER_REPLY` в idle)
  - для перевода статуса использует `project item id`, поэтому не зависит от ручного заполнения поля `Task ID`
  - `Task ID` берет из поля, либо извлекает `PL-xxx` из title
  - если `PL-xxx` отсутствует, использует fallback `ISSUE-<number>` по номеру Issue
  - при единственной задаче переводит ее в `Status/Flow=In Progress`
    - если `Status/Flow` апдейт временно недоступен, апдейт откладывается в runtime-очередь, claim не теряется
  - сохраняет текущий `Task ID` в `<state-dir>/project_task_id.txt` для последующего `task_finalize`
- `daemon_loop.sh [interval-sec]`
  - крутит `daemon_tick.sh` в цикле с lock-файлом и heartbeat-логом
  - при последовательных `WAIT_GITHUB_RATE_LIMIT` применяет экспоненциальный backoff сна (`base -> x2 -> x4`, по умолчанию `90 -> 180 -> 360`) и сбрасывает backoff после успешного non-rate-limit тика
  - перед каждым тиком получает свежий `GH_TOKEN` из локального auth endpoint (`/token`)
  - при ошибке auth-сервиса:
    - если включен `DAEMON_GH_TOKEN_FALLBACK_ENABLED` и доступен PAT (`DAEMON_GH_TOKEN`/`CODEX_GH_TOKEN`) — продолжает работу через fallback
    - иначе выставляет `WAIT_AUTH_SERVICE`
  - при auth-деградации пишет в detail явную причину (`AUTH_DEGRADED=1`, `AUTH_FALLBACK_*`) и отправляет Telegram-сигнал
  - пишет в `daemon_state_detail` явные health-маркеры: `GITHUB_STATUS=<...>` и `TELEGRAM_STATUS=<...>`
  - state `WAIT_GITHUB_RATE_LIMIT` трактуется как деградация `DEGRADED=GITHUB_GRAPHQL_RATE_LIMIT`
  - для GitHub/runtime-status деградации есть отдельные Telegram-сигналы без дублей:
    - `GITHUB_RUNTIME_WAIT` — отправляется только когда реально заблокирована `runtime`-очередь status-апдейтов (а не при пустой очереди)
    - `GITHUB_RUNTIME_RECOVERED` — GitHub снова отвечает, runtime-апдейты применились
  - после `GITHUB_RUNTIME_RECOVERED` при новом лаге снова отправляется `GITHUB_RUNTIME_WAIT` (повторный transition)
  - state `WAIT_DIRTY_WORKTREE` отправляет отдельные Telegram-алерты блокировки:
    - вход (`WAIT_DIRTY_WORKTREE_ENTER`)
    - изменение набора файлов (`WAIT_DIRTY_WORKTREE_CHANGED`)
    - reminder (`WAIT_DIRTY_WORKTREE_REMINDER`)
    - снятие блокировки (`DIRTY_WORKTREE_RESOLVED`)
  - формат dirty-worktree Telegram-алертов: заголовок `PLANKA: ...`, структурированные строки `Reason/State/Blocked/Tracked/Action/Time`, служебные поля остаются в `blockquote + code`
  - dirty-worktree алерты отправляются только если реально блокируется карточка из `Todo` (`WAIT_DIRTY_WORKTREE_BLOCKING_TODO=1`); в `idle` без `Todo` уведомления не шлются
  - различает сетевую деградацию и веточный блокер синхронизации (`WAIT_BRANCH_SYNC`)
  - отправляет локальные Telegram-алерты по деградации без спама:
    - вход в деградацию (`ENTER_DEGRADED`)
    - смена причины деградации (`DEGRADED_CHANGED`)
    - периодический reminder (`DEGRADED_REMINDER`, по умолчанию раз в 30 минут)
    - восстановление (`RECOVERED`)
  - при DNS-проблемах GitHub дополнительно проверяет `api.telegram.org`
  - если Telegram доступен, отправляет приоритетный сигнал через бота о GitHub DNS-деградации (`GITHUB_DNS_TELEGRAM_OK_*`)
- `daemon_install.sh [label] [interval-sec]`
  - создает канонический plist в host-local `.flow/launchd/<label>.plist` (обычно symlink на `<AI_FLOW_ROOT_DIR>/launchd/<project>`)
  - устанавливает symlink в `~/Library/LaunchAgents/<label>.plist` для `launchd`
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
  - для `daemon_state=WAIT_GITHUB_RATE_LIMIT` использует отдельный порог stale (чтобы легальный rate-limit backoff daemon не считался зависанием)
  - лестница восстановления:
    - `SOFT_DAEMON_TICK` (`daemon_tick`)
    - `MEDIUM_RESET_EXECUTOR` (`executor_reset` + `daemon_tick`)
    - `HARD_RESTART_DAEMON` (`daemon_uninstall` + `daemon_install`)
  - использует cooldown, чтобы не спамить recovery-действиями
  - в Telegram-алерте `Action` остается только в заголовке (`🛟 <project>: watchdog <ACTION>`), отдельный блок в теле содержит только `⚙️ Reason`
  - отправляет Telegram-сигнал о срабатывании recovery (если доступен бот)
- `watchdog_loop.sh [interval-sec]`
  - крутит `watchdog_tick.sh` в цикле с отдельным lock-файлом
  - перед каждым циклом обновляет `GH_TOKEN` через локальный auth endpoint
  - при ошибке auth-сервиса использует тот же fallback-флаг `DAEMON_GH_TOKEN_FALLBACK_ENABLED`; без fallback выставляет `watchdog_state=WAIT_AUTH_SERVICE`
- `watchdog_install.sh [label] [interval-sec]`
  - создает канонический plist в host-local `.flow/launchd/<label>.plist` для watchdog (обычно symlink на `<AI_FLOW_ROOT_DIR>/launchd/<project>`)
  - устанавливает symlink в `~/Library/LaunchAgents/<label>.plist`
- `watchdog_uninstall.sh [label]`
  - выгружает и удаляет watchdog-агент
- `watchdog_status.sh [label]`
  - проверяет, запущен ли watchdog-агент
- `task_finalize.sh`
  - читает `commit_message.txt`, `stage_paths.txt`, `project_task_id.txt` (или `daemon_active_task.txt`)
  - выполняет commit/push в текущую task-ветку
  - если текущая ветка не `development`, подтягивает в неё актуальный `development`, затем fast-forward вливает task-ветку обратно в `development`
  - создает PR `development -> main` или обновляет существующий
  - переводит задачу в `Status=Review`, `Flow=In Review` (можно переопределить через `FINAL_STATUS` и `FINAL_FLOW`)
  - если апдейт статуса временно недоступен, откладывает его в runtime-очередь без остановки финализации
  - публикует `CODEX_SIGNAL: AGENT_IN_REVIEW` и включает waiting-контекст `REVIEW_FEEDBACK` для комментариев в Issue
  - очищает входные файлы commit/PR и активный daemon-state (active), сохраняя review-waiting контекст
- `executor_build_prompt.sh <task-id> <issue-number> <output-file>`
  - собирает prompt executor из текста Issue и последнего ответа пользователя
- `executor_start.sh <task-id> <issue-number>`
  - запускает `executor_run.sh` в фоне и сохраняет pid/state
- `executor_run.sh <task-id> <issue-number>`
  - выполняет `codex exec --full-auto` с подготовленным prompt
  - пишет результат в `<state-dir>/executor.log` и обновляет state (`DONE/FAILED`)
  - обновляет heartbeat-файлы для диагностики "жив/завис"
- `executor_tick.sh <task-id> <issue-number>`
  - на каждом тике делает `project_status_runtime apply` (executor тоже подчищает отложенные status-апдейты)
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
  - сохраняет waiting-state в `<state-dir>/`, чтобы daemon ждал ответ пользователя
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
  - сохраняет ответ в `<state-dir>/daemon_user_reply.txt`
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
  - запускает auth-сервис, предварительно загружая `.flow/config/flow.env` (с legacy fallback через resolver)
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
- `status_snapshot.sh`
  - собирает единый JSON snapshot по локальным state-файлам (`daemon/watchdog/executor/queues/rate-limit/backlog-seed`)
  - для `executor` использует fallback из `watchdog_state_detail`, поэтому в idle видно `state=IDLE`, даже если `executor_*` файлы очищены
  - нормализует `overall_status` и `action_required` (например, `WAIT_DIRTY_WORKTREE + BLOCKING_TODO=0` трактуется как non-blocking warning)
- `ops_bot_service.js`
  - HTTP сервис с endpoint-ами: `GET /health`, `GET /ops/status`, `GET /ops/status.json`
  - Telegram webhook handler: `POST /telegram/webhook[/<secret>]`
  - невалидный webhook JSON -> `400 BAD_REQUEST`; payload > 1 MiB -> `413 PAYLOAD_TOO_LARGE`
  - update без команды обрабатывается безопасно (`200`, `command_handled=false`)
  - команды в чате: `/status`, `/summary [hours]`, `/help`, `/status_page`
  - `/status` агрегирует все известные project/runtime snapshots на этом automation-contour и отдает их отдельными блоками
- `ops_bot_start.sh`
  - запускает ops-бот сервис, предварительно загружая `.flow/config/flow.env` (с legacy fallback через resolver)
- `ops_bot_health.sh`
  - проверяет локальный `GET /health` ops-бота
- `ops_bot_post_smoke_check.sh`
  - локальный post-rollout чекер для `ISSUE-316`: собирает статус по `health/webhook/commands/status-page`
  - проверяет наличие `MANUAL_ROLLOUT_DONE` + полей `OPS_HEALTH/WEBHOOK_INFO/BOT_COMMANDS/OPS_STATUS_JSON` в входном файле (по умолчанию `.flow/state/codex/issue_285_manual_enriched.md`)
  - формирует структурированный отчет и список инцидентов (`.flow/state/codex/issue_316_post_smoke_report.md`)
- `ops_bot_pm2_ecosystem.config.cjs`
  - PM2 ecosystem-конфиг ops-бот сервиса (`autorestart`, отдельные log-файлы)
- `ops_bot_pm2_start.sh`
  - стартует ops-бот сервис под PM2 (или делает restart существующего процесса)
- `ops_bot_pm2_stop.sh`
  - останавливает и удаляет ops-бот сервис из PM2
- `ops_bot_pm2_restart.sh`
  - перезапускает ops-бот сервис в PM2
- `ops_bot_pm2_status.sh`
  - показывает состояние ops-бот сервиса в PM2 (`status`, `pid`, `restarts`, `uptime`)
- `ops_bot_pm2_health.sh`
  - проверяет, что PM2-процесс `online`, и валидирует `GET /health`
  - успешный сценарий: exit code `0`; при недоступности PM2/HTTP endpoint возвращает non-zero
- `ops_bot_webhook_register.sh`
  - читает env (`OPS_BOT_PUBLIC_BASE_URL`, `OPS_BOT_WEBHOOK_PATH`, `OPS_BOT_WEBHOOK_SECRET`, `OPS_BOT_TG_SECRET_TOKEN`, `OPS_BOT_TG_BOT_TOKEN`)
  - выполняет `setWebhook` + `getWebhookInfo` (`register`)
  - выполняет `deleteWebhook + setWebhook + getWebhookInfo` (`refresh`)
  - выполняет только `deleteWebhook` (`delete`)
  - выполняет только `getWebhookInfo` (`info`)
- `ops_bot_webhook_refresh.sh`
  - wrapper без аргументов для `ops_bot_webhook_register.sh refresh`
- `ops_remote_status_push.sh`
  - формирует payload из `status_snapshot.sh` и отправляет его в `OPS_REMOTE_STATUS_PUSH_URL`
  - в payload добавляет `profile`, `repo`, `label`; default `source` берется из `PROJECT_PROFILE`/repo, а не только из hostname
  - auth заголовок: `X-Ops-Status-Secret` из `OPS_REMOTE_STATUS_PUSH_SECRET`
  - используется `daemon_tick` на `EXIT` (fallback для старого запущенного `daemon_loop`) и `daemon_loop` по тикам для split runtime (локальная автоматика + удаленный ops-бот)
- `ops_remote_summary_push.sh`
  - формирует payload из `log_summary.sh --hours <window>` (окна из `OPS_REMOTE_SUMMARY_PUSH_HOURS`, по умолчанию `6`)
  - в payload добавляет `profile`, `repo`, `label`; remote ingest хранит summary раздельно по source
  - отправляет bundle summary в `OPS_REMOTE_SUMMARY_PUSH_URL` (`/ops/ingest/log-summary`) с заголовком `X-Ops-Status-Secret`
  - использует throttling по `OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC` (по умолчанию `300`) и backoff `OPS_REMOTE_SUMMARY_PUSH_ENDPOINT_MISSING_BACKOFF_SEC` для `404 endpoint not found`

Минимальный smoke-checklist для владельца окружения (rollout):
- `node -v`, `pm2 -v`, `jq --version`
- `.flow/shared/scripts/run.sh ops_bot_pm2_start`
- `.flow/shared/scripts/run.sh ops_bot_pm2_status` (ожидается `PM2_STATUS=online`)
- `.flow/shared/scripts/run.sh ops_bot_pm2_health` (ожидается exit code `0`)
- `.flow/shared/scripts/run.sh ops_bot_post_smoke_check` (агрегированный post-smoke отчет; exit code `0` при accepted, `2` при инцидентах)
- `.flow/shared/scripts/run.sh ops_bot_webhook_register register` (ожидается `WEBHOOK_SET_OK=1` и `WEBHOOK_INFO_OK=1`)
- `.flow/shared/scripts/run.sh ops_bot_webhook_refresh` (ожидается `WEBHOOK_DELETE_OK=1`, `WEBHOOK_SET_OK=1`, `WEBHOOK_INFO_OK=1`)
- `.flow/shared/scripts/run.sh ops_bot_webhook_register info` (ожидается `WEBHOOK_INFO_OK=1`)
- `.flow/shared/scripts/run.sh ops_remote_status_push` (ожидается `OPS_REMOTE_PUSH_OK=1` при настроенных `OPS_REMOTE_STATUS_PUSH_*`)
- `.flow/shared/scripts/run.sh ops_remote_summary_push` (ожидается `OPS_REMOTE_SUMMARY_PUSH_OK=1` при настроенных `OPS_REMOTE_SUMMARY_PUSH_*`)
- HTTP-проверки: `GET /health`, `GET /ops/status`, `GET /ops/status.json`
- webhook negative-checks: невалидный JSON -> `400`, слишком большой payload -> `413`, update без команды -> `200 command_handled=false`
- Telegram webhook + команды: `/help`, `/status`, `/summary 6`, `/status_page`

Логи демона:
- `<log-dir>/runtime/daemon.log` — heartbeat и результат `daemon_tick`
- `<log-dir>/runtime/launchd.out.log` — stdout агента `launchd`
- `<log-dir>/runtime/launchd.err.log` — stderr агента `launchd`
- `<log-dir>/runtime/watchdog.log` — heartbeat watchdog и recovery-действия
- `<state-dir>/watchdog_state.txt` — агрегированный статус watchdog
- `<state-dir>/watchdog_state_detail.txt` — причина/деталь статуса watchdog
- `<state-dir>/watchdog_last_action.txt` — последнее recovery-действие
- `<state-dir>/watchdog_last_action_epoch.txt` — timestamp последнего recovery-действия
- `<log-dir>/runtime/watchdog.launchd.out.log` — stdout watchdog-агента
- `<log-dir>/runtime/watchdog.launchd.err.log` — stderr watchdog-агента
- `.flow/tmp/` — временные toolkit-артефакты и migration manifest; не смешивается с runtime-state профиля
- `<state-dir>/daemon_user_reply.txt` — последний ответ пользователя из Issue-комментариев
- `<state-dir>/daemon_review_task_id.txt` — задача, ожидающая review-feedback
- `<state-dir>/daemon_review_item_id.txt` — project item id задачи в review-feedback режиме
- `<state-dir>/daemon_review_issue_number.txt` — issue number задачи в review-feedback режиме
- `<state-dir>/daemon_review_pr_number.txt` — PR number для review-feedback режима
- `<state-dir>/daemon_state.txt` — текущий агрегированный state демона (`IDLE_NO_TASKS`, `WAIT_OPEN_PR`, `WAIT_GITHUB_OFFLINE` и т.д.)
- `<state-dir>/daemon_state_detail.txt` — краткая причина/деталь текущего state, включая признаки деградации (`DEGRADED=GITHUB_DNS_OFFLINE`, `DEGRADED=PENDING_OUTBOX:<n>` и т.п.)
- `<state-dir>/daemon_notify_mode.txt` — последний режим уведомлений (`degraded|healthy`)
- `<state-dir>/daemon_notify_last_epoch.txt` — timestamp последней попытки локального Telegram-уведомления
- `<state-dir>/daemon_notify_last_signature.txt` — подпись последнего состояния, по которой определяется `DEGRADED_CHANGED`
- `<log-dir>/runtime/graphql_rate_stats.log` — журнал rate-limit событий GraphQL (одно событие = окно от первого успешного запроса после лимита до нового лимита)
- `<state-dir>/graphql_rate_window_state.txt` — состояние текущего окна (`WAIT_SUCCESS|RUNNING`)
- `<state-dir>/graphql_rate_window_start_epoch.txt` — epoch старта текущего окна
- `<state-dir>/graphql_rate_window_start_utc.txt` — UTC-старт текущего окна
- `<state-dir>/graphql_rate_window_requests.txt` — число успешных GraphQL-запросов в текущем окне
- `<state-dir>/graphql_rate_last_success_utc.txt` — время последнего успешного GraphQL-запроса
- `<state-dir>/graphql_rate_last_limit_utc.txt` — время последнего зафиксированного rate-limit события
- `<log-dir>/runtime/executor.log` — полный лог автономного executor
- `<state-dir>/executor_state.txt` — состояние executor (`RUNNING|DONE|FAILED`)
- `<state-dir>/executor_pid.txt` — pid фонового executor-процесса
- `<state-dir>/executor_last_exit_code.txt` — код завершения последнего executor запуска
- `<state-dir>/executor_heartbeat_utc.txt` — время последнего heartbeat executor
- `<state-dir>/executor_heartbeat_epoch.txt` — epoch-время последнего heartbeat executor
- `<state-dir>/outbox/` — pending GitHub-действия (очередь)
- `<state-dir>/outbox_payloads/` — payload-файлы для pending действий
- `<state-dir>/outbox_failed/` — non-retryable ошибки outbox
- `<log-dir>/pm2/ops_bot.out.log` — stdout ops-бот сервиса (PM2)
- `<log-dir>/pm2/ops_bot.err.log` — stderr ops-бот сервиса (PM2)

Быстрый анализ частоты GraphQL rate limit:
- последние события: `tail -n 20 <log-dir>/runtime/graphql_rate_stats.log`
- среднее число успешных GraphQL-запросов до нового лимита:
  `awk -F'\t' '/EVENT=RATE_LIMIT/ { for(i=1;i<=NF;i++) if($i ~ /^requests=/){ split($i,a,"="); sum+=a[2]; n++ } } END { if(n) printf("avg_requests=%.2f events=%d\n", sum/n, n); else print "no_data" }' <log-dir>/runtime/graphql_rate_stats.log`
- средняя длительность окна (сек):
  `awk -F'\t' '/EVENT=RATE_LIMIT/ { for(i=1;i<=NF;i++) if($i ~ /^duration_sec=/){ split($i,a,"="); sum+=a[2]; n++ } } END { if(n) printf("avg_duration_sec=%.2f events=%d\n", sum/n, n); else print "no_data" }' <log-dir>/runtime/graphql_rate_stats.log`

Быстрая проверка включения App auth:
- `.flow/shared/scripts/run.sh gh_app_auth_pm2_health`
- `cat <state-dir>/daemon_state.txt`
- `cat <state-dir>/daemon_state_detail.txt`
- при необходимости: `tail -n 80 <log-dir>/runtime/daemon.log`

## Подготовка
Скрипты должны быть исполняемыми:

```bash
chmod +x .flow/shared/scripts/*.sh
```

Опциональные переменные для локальных Telegram-алертов демона:
- `DAEMON_TG_BOT_TOKEN` (или `TG_BOT_TOKEN`)
- `DAEMON_TG_CHAT_ID` (или `TG_CHAT_ID`)
- `DAEMON_TG_ENV_FILE` (путь к env-файлу; по умолчанию используется `.flow/config/flow.env` с legacy fallback через resolver)
- `DAEMON_TG_REMINDER_SEC` (интервал reminder в секундах, минимум 60; по умолчанию 1800)
- `DAEMON_TG_GH_DNS_REMINDER_SEC` (интервал напоминаний именно для деградации `GITHUB_DNS_OFFLINE` при доступном Telegram; минимум 60, по умолчанию 300)
- `DAEMON_TG_DIRTY_REMINDER_SEC` (интервал reminder для блокировки `WAIT_DIRTY_WORKTREE`; минимум 60, по умолчанию 600)
- `DAEMON_GH_TOKEN_FALLBACK_ENABLED` (или `CODEX_GH_TOKEN_FALLBACK_ENABLED`) — включает аварийный fallback на `DAEMON_GH_TOKEN`/`CODEX_GH_TOKEN` при недоступном auth endpoint
- `DAEMON_GH_PROJECT_TOKEN` (или `CODEX_GH_PROJECT_TOKEN`) — отдельный PAT для Project v2 в hybrid mode (если Project user-owned)
- `DEPENDENCY_ISSUE_RESOLVED_CACHE_TTL_SEC` — TTL (сек) кэша результата `dependency_issue_resolved`; `0` отключает кэш (по умолчанию `180`)
- `WATCHDOG_DAEMON_LABEL` (какой daemon label перезапускать при hard recovery; по умолчанию формируется из label текущего профиля)
- `WATCHDOG_DAEMON_INTERVAL_SEC` (интервал daemon после hard restart; по умолчанию 45)
- `WATCHDOG_COOLDOWN_SEC` (минимальная пауза между recovery-действиями; по умолчанию 120)
- `WATCHDOG_EXECUTOR_STALE_SEC` (порог stale heartbeat executor; по умолчанию 180)
- `WATCHDOG_DAEMON_LOG_STALE_SEC` (порог stale daemon log/lock; по умолчанию 180)
- `WATCHDOG_DAEMON_LOG_STALE_RATE_LIMIT_SEC` (порог stale daemon log/lock для `WAIT_GITHUB_RATE_LIMIT`; по умолчанию `DAEMON_RATE_LIMIT_MAX_SLEEP_SEC + WATCHDOG_DAEMON_INTERVAL_SEC + 60`)
- `OPS_BOT_BIND` (bind ops-бот сервиса; по умолчанию `127.0.0.1`)
- `OPS_BOT_PORT` (порт ops-бот сервиса; по умолчанию `8790`)
- `OPS_BOT_USE_DEFAULT` (если `1/true/yes/on`, `onboarding_audit` считает допустимым shared/default local ops-bot на текущем хосте: `PM2_APP_NAME=planka-ops-bot`, `BIND=127.0.0.1`, `PORT=8790`; public/remote contour при этом оценивается отдельно через `OPS_BOT_PUBLIC_BASE_URL` и `OPS_REMOTE_*`)
- `OPS_BOT_WEBHOOK_PATH` (базовый path webhook; по умолчанию `/telegram/webhook`)
- `OPS_BOT_WEBHOOK_SECRET` (добавляется в path webhook для защиты URL)
- `OPS_BOT_TG_SECRET_TOKEN` (опциональная проверка заголовка `X-Telegram-Bot-Api-Secret-Token`)
- `OPS_BOT_INGEST_ENABLED` (включает ingest endpoint для внешнего runtime snapshot)
- `OPS_BOT_INGEST_PATH` (path ingest endpoint; по умолчанию `/ops/ingest/status`)
- `OPS_BOT_INGEST_SECRET` (секрет заголовка `X-Ops-Status-Secret` для ingest POST)
- `OPS_BOT_SUMMARY_INGEST_PATH` (path ingest endpoint для remote `log_summary`; по умолчанию `/ops/ingest/log-summary`)
- `OPS_BOT_SUMMARY_INGEST_SECRET` (секрет для summary-ingest; если не задан — используется `OPS_BOT_INGEST_SECRET`)
- `OPS_BOT_REMOTE_STATE_DIR` (каталог раздельного remote ingest storage; по умолчанию `.flow/state/ops-bot/remote`)
- `OPS_BOT_REMOTE_SNAPSHOT_FILE` (legacy-файл кеша последнего принятого удаленного snapshot; по умолчанию `.flow/state/ops-bot/remote/_legacy/snapshot.json`)
- `OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC` (TTL удаленного snapshot в секундах; по умолчанию `600`)
- `OPS_BOT_REMOTE_SUMMARY_FILE` (legacy-файл кеша последнего принятого удаленного summary bundle; по умолчанию `.flow/state/ops-bot/remote/_legacy/summary.json`)
- `OPS_BOT_REMOTE_SUMMARY_TTL_SEC` (TTL удаленного summary bundle в секундах; по умолчанию `1200`)
- `OPS_BOT_ALLOWED_CHAT_IDS` (CSV списка разрешенных chat_id; если задано — остальные игнорируются)
- `OPS_BOT_PUBLIC_BASE_URL` (внешний URL status/webhook server для ops-bot: используется для `/status_page`, Telegram webhook registration и публичного ingress, например `https://ops.example.com`)
- `OPS_BOT_REFRESH_SEC` (интервал автообновления `/ops/status` в секундах; по умолчанию `5`)
- `OPS_BOT_CMD_TIMEOUT_MS` (таймаут внутренних команд snapshot/summary; по умолчанию `10000`)
- `OPS_BOT_TG_BOT_TOKEN` (опциональный токен бота; fallback chain: `OPS_BOT_TG_BOT_TOKEN -> DAEMON_TG_BOT_TOKEN -> TG_BOT_TOKEN`)
- `OPS_BOT_PM2_APP_NAME` (имя PM2 процесса ops-бота; по умолчанию `planka-ops-bot`)
- `OPS_REMOTE_STATUS_PUSH_ENABLED` (включает push локального snapshot на удаленный ingest endpoint)
- `OPS_REMOTE_STATUS_PUSH_URL` (полный URL ingest endpoint, например `https://planka-dev.ewg40.ru/ops/ingest/status`)
- `OPS_REMOTE_STATUS_PUSH_SECRET` (секрет заголовка `X-Ops-Status-Secret` для push)
- `OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC` (HTTP timeout push-запроса; по умолчанию `6`)
- `OPS_REMOTE_STATUS_PUSH_SOURCE` (лейбл источника; по умолчанию `PROJECT_PROFILE`, затем repo-name, затем hostname)
- `OPS_REMOTE_SUMMARY_PUSH_ENABLED` (включает push локального summary bundle на удаленный ingest endpoint)
- `OPS_REMOTE_SUMMARY_PUSH_URL` (полный URL summary ingest endpoint, например `https://planka-dev.ewg40.ru/ops/ingest/log-summary`)
- `OPS_REMOTE_SUMMARY_PUSH_SECRET` (секрет заголовка `X-Ops-Status-Secret` для summary push; fallback к `OPS_REMOTE_STATUS_PUSH_SECRET`)
- `OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC` (HTTP timeout summary push-запроса; по умолчанию `8`)
- `OPS_REMOTE_SUMMARY_PUSH_SOURCE` (лейбл источника summary push; по умолчанию `PROJECT_PROFILE`, затем repo-name, затем hostname)
- `OPS_REMOTE_SUMMARY_PUSH_HOURS` (CSV окон summary для push; по умолчанию `6`)
- `OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC` (минимальный интервал между summary push; по умолчанию `300`)
- `OPS_REMOTE_SUMMARY_PUSH_ENDPOINT_MISSING_BACKOFF_SEC` (backoff при `404 endpoint not found`; по умолчанию `3600`)
- `AI_FLOW_ROOT_DIR` (host-level shared flow root; по умолчанию `<sites-root>/.ai-flow`)
- `FLOW_LOGS_DIR` (project log dir; по умолчанию `<AI_FLOW_ROOT_DIR>/logs/<project-profile-or-repo>`)
