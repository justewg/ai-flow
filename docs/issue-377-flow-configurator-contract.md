# ISSUE-377 Спека flow-конфигуратора

## Цель

Зафиксировать верхнеуровневый контракт flow-конфигуратора, который:

1. доводит новый или существующий repo до рабочего flow-контура без ручной сборки команд;
2. переиспользует существующие toolkit-команды как backend-слой;
3. умеет безопасно возобновляться после прерывания и повторно запускаться без разрушения уже настроенного проекта.

## Границы ответственности

Flow-конфигуратор не дублирует логику shared toolkit. Он отвечает только за:

- discovery текущего состояния repo;
- последовательность вопросов и safe defaults;
- запись подтверждённых значений в нужные config-файлы;
- orchestration вызовов toolkit-команд;
- resume/state, preview изменений и safe-overwrite.

Shared toolkit остаётся источником истины для:

- materialize repo overlay через `apply_migration_kit`;
- создания `flow.env`, state/layout и launchd label defaults через `profile_init`;
- env/repo/GitHub-проверок через `onboarding_audit`;
- установки daemon/watchdog через `profile_init install` и вложенные `daemon_install`/`watchdog_install`;
- preflight/smoke summary через `profile_init preflight`.

Отдельный gap: bootstrap `.flow/` и подключение `/.flow/shared` как submodule не покрыты текущими toolkit-командами. Этот шаг должен быть реализован отдельным bootstrap-слоем в `ISSUE-378`; текущая спека фиксирует его как шаг визарда, но не переносит в него логику `profile_init`/`onboarding_audit`.

## Режимы входа

| Режим | Как определяется | С чего начинает визард | Когда считается завершённым |
| --- | --- | --- | --- |
| `fresh_repo` | Нет `/.flow/shared/scripts/run.sh`, нет `/.flow/config/flow.env`, либо repo ещё не materialized под flow | bootstrap `.flow` и toolkit, затем первичная инициализация профиля | Созданы toolkit/layout/config, `profile_init install` и `preflight` прошли без блокирующих ошибок |
| `partial_repo` | Toolkit и/или `flow.env` уже есть, но `onboarding_audit`/`preflight` возвращают `CHECK_FAIL` или отсутствуют обязательные артефакты | discovery + дозаполнение только missing/invalid значений | Все обязательные проверки зелёные, пропущенные шаги материализованы |
| `rerun_reconfigure` | `flow.env` и runtime уже есть, пользователь запускает визард повторно для проверки или изменения конфигурации | discovery + diff against current config | Изменения применены по подтверждённому diff, `preflight` повторно зелёный |

## State-модель и точки возобновления

### Жизненный цикл визарда

| State | Что происходит | Resume-поведение |
| --- | --- | --- |
| `discovering` | Сбор фактов о repo, toolkit, env и runtime | Повторно запускает discovery, затем восстанавливает прогресс по state-файлу |
| `bootstrapping` | Создание `.flow/`, подключение `/.flow/shared`, optional `apply_migration_kit` | Повторно проверяет уже созданные артефакты и продолжает со следующего неполного шага |
| `questionnaire` | Сбор ответов по profile/repo/project/auth/services | Возобновляется с первого `pending` вопроса; secrets запрашиваются заново |
| `review` | Показывает diff, overwrite-риски, список артефактов `create/update/skip` | Повторно показывает только неподтверждённые конфликты |
| `applying` | Пишет config и вызывает toolkit-команды | Повторно начинает с последнего неуспешного backend-step; завершённые шаги не повторяет без причины |
| `installing` | Запускает `profile_init install` | При повторном запуске сначала сверяет текущий env/state и затем либо пропускает, либо повторяет install |
| `preflight` | Запускает `profile_init preflight` и формирует summary | Повторно прогоняет preflight целиком, потому что это финальная проверка |
| `done` | Сохраняет summary последнего успешного запуска | Новый запуск переводит визард в `discovering` и работает как `rerun_reconfigure` |
| `blocked` | Нужен missing secret, пользовательское подтверждение overwrite или внешний bootstrap-gap | Resume возможен после появления недостающего значения/подтверждения |
| `failed` | Backend-команда завершилась ошибкой, которую нельзя автоматически классифицировать | Resume стартует с failed-step после повторного discovery |

### Точки resume

Resume state пишется после:

1. завершения discovery;
2. подтверждения каждой группы вопросов;
3. формирования overwrite-preview;
4. успешного завершения каждого backend-вызова;
5. финального preflight-summary.

Секреты не сохраняются в открытом виде. После resume визард может продолжить без повторного ввода обычных ответов, но значения secret-полей должны вводиться заново, если они ещё не записаны в конечный config-файл.

## Формат промежуточного state

Канонический файл: `.flow/tmp/wizard/flow-configurator-state.json`

Причина выбора:

- путь существует в repo-контуре и не зависит от уже известного `PROJECT_PROFILE`;
- его можно создать ещё до materialize `CODEX_STATE_DIR`;
- state не смешивается с runtime-артефактами daemon/watchdog.

Минимальный контракт:

```json
{
  "schema_version": 1,
  "wizard": "flow-configurator",
  "scenario": "partial_repo",
  "status": "questionnaire",
  "current_step": "github_project",
  "repo": {
    "root": "/private/var/sites/acme-app",
    "origin": "git@github.com:acme/acme-app.git",
    "head_ref": "task/issue-377",
    "dirty_tracked": false
  },
  "steps": {
    "discover": { "status": "completed", "completed_at": "2026-03-13T08:12:05Z" },
    "bootstrap": { "status": "skipped" },
    "github_project": { "status": "in_progress" }
  },
  "answers": {
    "project_profile": {
      "value": "acme",
      "source": "derived:repo-name",
      "status": "confirmed"
    },
    "github_repo": {
      "value": "acme/acme-app",
      "source": "derived:git-origin",
      "status": "confirmed"
    },
    "daemon_gh_project_token": {
      "masked": "ghp_***9K2",
      "source": "manual",
      "status": "pending-reentry",
      "sensitive": true
    }
  },
  "pending_overwrites": [
    {
      "path": ".github/workflows/review.yml",
      "reason": "overlay-differs",
      "decision": "pending"
    }
  ],
  "backend_runs": [
    {
      "command": "onboarding_audit",
      "args": ["--profile", "acme"],
      "exit_code": 0,
      "summary": {
        "ok": 27,
        "warn": 3,
        "fail": 0
      }
    }
  ]
}
```

Правила хранения state:

- `answers[*].value` разрешён только для non-secret значений;
- для secret-полей хранятся только `masked`, `source`, `status`;
- `pending_overwrites` содержит только конфликтующие пути и решение `pending|accepted|rejected`;
- `backend_runs` хранит summary/stdout markers, но не секреты и не полные токены;
- при успешном завершении state остаётся как last-run snapshot и может быть использован для следующего `rerun_reconfigure`.

## Пошаговый UX сценарий

### 1. Discovery

Визард всегда начинает с автоанализа:

1. Проверяет наличие `.flow/`, `/.flow/shared/scripts/run.sh`, `.flow/config/flow.env`.
2. Если toolkit уже materialized, запускает `onboarding_audit --skip-network`.
3. Если профиль уже известен или найден в `flow.env`, повторяет `onboarding_audit --profile <name>`.
4. Если `flow.env` выглядит полным, запускает `profile_init preflight --profile <name>` для фиксации текущего baseline.

Пользователь видит краткий classification:

- что уже найдено;
- чего не хватает;
- какие шаги будут `create`, `update`, `skip`.

### 2. Bootstrap

Шаг обязателен только для `fresh_repo` или сломанного bootstrap.

Порядок:

1. Создать repo-local `.flow/` и служебный каталог `.flow/tmp/wizard/`.
2. Подключить `/.flow/shared` как submodule или использовать заранее распакованный migration kit.
3. Если выбран migration-kit path, вызвать `apply_migration_kit --project <profile>`.
4. Если `apply_migration_kit` не использовался, вызвать `profile_init init --profile <profile>` после выбора профиля.

Правило выбора:

- если в repo уже есть распакованный kit с `.flow/config/flow.sample.env` и overlay-manifest, предпочитается `apply_migration_kit`;
- если repo чистый и нужен канонический reusable layout, предпочитается submodule/bootstrap path;
- bootstrap layer не должен вручную генерировать `flow.env` вместо `profile_init init` и не должен вручную раскладывать overlay вместо `apply_migration_kit`.

### 3. Questionnaire

Вопросы задаются группами в таком порядке:

1. `profile/repo`
2. `github project`
3. `auth`
4. `optional notifications/services`
5. `advanced runtime overrides` только если пользователь включил advanced-mode или если discovery нашёл non-default layout

На каждом шаге визард:

- показывает уже найденный default и источник;
- объясняет, где взять значение, если оно не найдено;
- сразу валидирует формат;
- не спрашивает то, что можно безопасно вывести из уже существующего config без изменения смысла.

### 4. Review и safe-overwrite

Перед записью визард показывает:

- итоговый diff по `flow.env` и другим управляемым файлам;
- конфликтующие файлы overlay;
- список секретов, которые будут записаны или оставлены без изменений;
- список команд, которые будут вызваны дальше.

Пользователь может принять одно из решений:

1. `apply_all`
2. `apply_non_conflicting_only`
3. `edit_answers`
4. `cancel`

### 5. Apply

Порядок вызовов backend-слоя:

1. `apply_migration_kit --project <profile>` только если нужен repo overlay/materialize sample env;
2. `profile_init init --profile <profile>` если `flow.env` и state-layout ещё не materialized или если пользователь явно подтвердил `--force`;
3. запись/merge подтверждённых значений в `.flow/config/flow.env` и, при необходимости, `.env`/`.env.deploy`;
4. `profile_init install --profile <profile>`;
5. `profile_init preflight --profile <profile>`.

### 6. Result

Финальный экран всегда содержит:

- итоговый режим (`fresh_repo`, `partial_repo`, `rerun_reconfigure`);
- список созданных и обновлённых артефактов;
- summary `CHECK_FAIL/CHECK_WARN`, если что-то осталось;
- smoke-команды из `profile_init preflight`;
- что осталось вручную вне scope визарда, например repo Actions secrets или external GitHub App setup.

## Матрица вопросов

### Обязательные вопросы

| Вопрос | Куда пишется | Когда задаётся | Default | Validation | Где брать значение |
| --- | --- | --- | --- | --- | --- |
| `bootstrap_source` | шаг визарда, не env-ключ | Только если нет toolkit/layout | `shared_submodule`, если repo пустой; `migration_kit`, если kit уже распакован | одно из `shared_submodule`, `migration_kit`, `existing_checkout` | Из текущего состояния repo и решения владельца окружения |
| `project_profile` | `PROJECT_PROFILE` | Всегда, если не подтверждён ранее | slug имени repo или текущее значение из `flow.env` | после slugify должно быть непустым; рекомендуется `^[a-z0-9][a-z0-9-]*$` | Имя проекта/repo; при повторном запуске брать из `flow.env` |
| `github_repo` | `GITHUB_REPO` | Всегда | `origin` remote, нормализованный до `owner/repo` | формат `owner/repo`; при наличии git remote должен совпадать с `origin` либо быть явно подтверждён как override | `git remote get-url origin`, GitHub repo URL |
| `flow_base_branch` | `FLOW_BASE_BRANCH` | Всегда | текущее значение из env, иначе `main` | непусто, не равно `FLOW_HEAD_BRANCH`; audit потом проверяет наличие ветки | Из git-flow repo, обычно `main` |
| `flow_head_branch` | `FLOW_HEAD_BRANCH` | Всегда | текущее значение из env, иначе `development` | непусто, не равно `FLOW_BASE_BRANCH`; audit потом проверяет наличие ветки | Из git-flow repo, обычно `development` |
| `project_owner` | `PROJECT_OWNER` | Всегда | owner из `GITHUB_REPO` или текущего env | `@me` либо GitHub login без пробелов | Из URL Project v2: `/users/<owner>/projects/...` или `/orgs/<owner>/projects/...` |
| `project_number` | `PROJECT_NUMBER` | Всегда | текущее значение из env; иначе пусто | целое число `> 0` | Из URL Project v2 в GitHub UI |
| `project_id` | `PROJECT_ID` | Если не удалось автоматически определить по `owner/number` | auto-resolve через `gh project view <number> --owner <owner> --format json --jq '.id'`; fallback: текущее значение из env | начинается с `PVT_`; если доступен network-check, должен совпасть с `gh project view` | `gh project view`, GraphQL/API |
| `daemon_gh_project_token` | `DAEMON_GH_PROJECT_TOKEN` | Всегда | текущее значение не раскрывается, только статус `already-set` | непусто; фактическую работоспособность и scopes валидирует `onboarding_audit` | GitHub UI: classic PAT со scopes `repo`, `read:project`, `project` |
| `auth_mode` | набор ключей `GH_APP_*` и/или `DAEMON_GH_TOKEN*` | Всегда | `shared_app_service`, если уже есть service coordinates; иначе `dedicated_app_service`; `pat_fallback` только по явному выбору | одно из `shared_app_service`, `dedicated_app_service`, `pat_fallback` | Из существующего host-level контура и желаемого режима эксплуатации |

### Условные вопросы

| Вопрос | Куда пишется | Когда задаётся | Default | Validation | Где брать значение |
| --- | --- | --- | --- | --- | --- |
| `apply_repo_overlay` | шаг визарда / решение по `apply_migration_kit` | Если выбран `migration_kit` и в repo есть overlay-манифест | `true`, если `.github/workflows/` ещё не materialized; иначе `false` | если есть diff по target-файлам, требуется явное подтверждение overwrite | Из `.flow/config/root/github-actions.required-files.txt` и текущего содержимого `.github/` |
| `gh_app_internal_secret` | `GH_APP_INTERNAL_SECRET` | Для `shared_app_service` и `dedicated_app_service` | статус `already-set`, если значение уже есть; иначе пусто | непусто; рекомендуется длина `>= 16` | Из владельца GitHub App auth-service |
| `gh_app_id` | `GH_APP_ID` | Только для `dedicated_app_service` или если audit не нашёл значение | текущее значение из `.env`, `.env.deploy` или `flow.env` | целое число `> 0` | GitHub App settings |
| `gh_app_installation_id` | `GH_APP_INSTALLATION_ID` | Только для `dedicated_app_service` или если audit не нашёл значение | текущее значение из `.env`, `.env.deploy` или `flow.env` | целое число `> 0` | GitHub App installation details / API |
| `gh_app_private_key_path` | `GH_APP_PRIVATE_KEY_PATH` | Только для `dedicated_app_service` или если audit не нашёл значение | текущее значение из `.env`, `.env.deploy` или `flow.env` | путь существует; рекомендуется вне repo | Локальный path к `.pem`, например `<HOME>/.secrets/gh-apps/...` |
| `gh_app_service_coordinates` | `DAEMON_GH_AUTH_TOKEN_URL` или `GH_APP_BIND` + `GH_APP_PORT` + optional `GH_APP_PM2_APP_NAME` | Для `shared_app_service`/`dedicated_app_service` | existing coordinates; иначе `127.0.0.1:8787`, PM2 app name `<profile>-gh-app-auth` | либо валидный `http(s)://` URL, либо `bind` + порт `1..65535`; порт не должен конфликтовать с уже занятым | Из host-level auth-service runtime или планируемой PM2-конфигурации |
| `daemon_gh_token_fallback_enabled` | `DAEMON_GH_TOKEN_FALLBACK_ENABLED` | Только если пользователь включает аварийный fallback | `0` | boolean `0/1` | Выбор пользователя; включать только как аварийный режим |
| `daemon_gh_token` | `DAEMON_GH_TOKEN` | Только если включён fallback | пусто или статус `already-set` | непусто, если fallback включён | GitHub PAT, если auth-service временно недоступен |
| `daemon_tg_bot_token` | `DAEMON_TG_BOT_TOKEN` | Если включены локальные Telegram alerts | пусто или статус `already-set` | непусто | BotFather |
| `daemon_tg_chat_id` | `DAEMON_TG_CHAT_ID` | Если включены локальные Telegram alerts | пусто или статус `already-set` | integer; допустимы отрицательные значения для supergroup | Telegram `getUpdates`, `getChat` или текущий бот-контур |
| `ops_bot_mode` | `OPS_BOT_USE_DEFAULT` и связанные `OPS_BOT_*` | Если пользователь хочет status/dashboard/Telegram ops-bot | `disabled`; для existing setup использовать текущее значение | одно из `disabled`, `shared`, `dedicated` | Из желаемой схемы ops-бота на хосте |
| `ops_bot_allowed_chat_ids` | `OPS_BOT_ALLOWED_CHAT_IDS` | Если включён ops-bot | текущее значение или пусто | CSV/whitespace-separated список chat id без мусора | Telegram chat ids, где бот должен отвечать |
| `ops_bot_public_base_url` | `OPS_BOT_PUBLIC_BASE_URL` | Если ops-bot должен принимать внешний webhook или отдавать status page | текущее значение или пусто | валидный `https://` URL | URL внешнего ingress/reverse proxy |
| `ops_bot_tg_bot_token` | `OPS_BOT_TG_BOT_TOKEN` | Если включён ops-bot и нет fallback chain | текущее значение или reuse `DAEMON_TG_BOT_TOKEN` по явному согласию | непусто | BotFather или уже существующий daemon bot token |

### Advanced-вопросы

| Вопрос | Куда пишется | Когда задаётся | Default | Validation | Где брать значение |
| --- | --- | --- | --- | --- | --- |
| `ai_flow_root_dir` | `AI_FLOW_ROOT_DIR` | Только в advanced-mode или если discovery нашёл non-default layout | не писать ключ вовсе и использовать toolkit default | абсолютный путь | Host-level runtime root, например `<sites-root>/.ai-flow` |
| `watchdog_daemon_interval_sec` | `WATCHDOG_DAEMON_INTERVAL_SEC` | Advanced-mode или если пользователь хочет override | `45` | integer `>= 10` | Из требуемого polling interval |
| `executor_codex_bypass_sandbox` | `EXECUTOR_CODEX_BYPASS_SANDBOX` | Только если на хосте реально нужен direct full-access режим | текущее значение или `0` | boolean `0/1` | Из политики окружения executor |
| `global_env_target` | `.env` или `.env.deploy` | Если нужно писать host-level `GH_APP_*`/`OPS_BOT_*` значения | `.env.deploy` для deploy/runtime-контура, иначе `.env` | файл должен существовать или быть явно создан по подтверждению пользователя | Из соглашения consumer-project |

### Автовычисляемые значения, которые визард не должен спрашивать без необходимости

| Значение | Как вычисляется | Validation | Источник |
| --- | --- | --- | --- |
| `CODEX_STATE_DIR` | default от `profile_init init`; при non-default root: `<AI_FLOW_ROOT_DIR>/state/<profile>` | путь должен быть доступен для записи | `profile_init` и `AI_FLOW_ROOT_DIR` |
| `FLOW_STATE_DIR` | дублирует `CODEX_STATE_DIR` | должен совпадать с `CODEX_STATE_DIR`, если пользователь не запросил особый override | `profile_init` |
| `daemon_label` | `${FLOW_LAUNCHD_NAMESPACE:-com.flow}.codex-daemon.<profile>` | label уникален на хосте | `profile_init` |
| `WATCHDOG_DAEMON_LABEL` | равен вычисленному `daemon_label`, если не задан отдельно | должен указывать на daemon текущего профиля | `profile_init` |
| `.flow/config/flow.env` | canonical path из toolkit resolver | path в repo writable | `codex_resolve_flow_env_file` |
| `.flow/launchd` | canonical symlink/dir, который подготавливает `profile_init init/install` | путь должен вести в корректный host-level launchd dir | `profile_init` |
| `FLOW_LOGS_DIR` | default `<AI_FLOW_ROOT_DIR>/logs/<profile>` | путь writable | toolkit resolver |

## Контракт визарда с existing toolkit

| Backend-команда | Когда вызывает визард | Какие входы готовит визард | Что читает из вывода | Что остаётся на стороне toolkit |
| --- | --- | --- | --- | --- |
| `.flow/shared/scripts/run.sh onboarding_audit [--profile <name>] [--skip-network]` | discovery в начале и повторная валидация после записи config | наличие toolkit; optional `--profile`; optional `--skip-network` на первом проходе | строки `CHECK_OK`, `CHECK_WARN`, `CHECK_FAIL`, `ACTION`; итоговые счётчики | проверка repo/env/GitHub/toolkit/secrets и action hints |
| `.flow/shared/scripts/run.sh apply_migration_kit --project <name>` | только в bootstrap-path с migration kit | выбранный `project_profile`, подтверждение по overlay conflicts | созданные артефакты и exit code | materialize `.flow/config/flow.env`, `.flow/config/flow.sample.env`, manifests и repo overlay |
| `.flow/shared/scripts/run.sh profile_init init --profile <name>` | если env/state-layout ещё не materialized | `project_profile`, optional explicit overrides, `--force` только после confirm | `ENV_TEMPLATE_WRITTEN`, `ENV_TEMPLATE_EXISTS`, `FLOW_SAMPLE_ENV_WRITTEN`, `STATE_DIR_READY` | создание env template, state dir, launchd dir и namespace-layout |
| `.flow/shared/scripts/run.sh profile_init install --profile <name>` | после подтверждённой записи config или если runtime missing/broken | готовый `flow.env`, optional host-global env, known profile | exit code и stdout/stderr install | runtime layout + вызовы `daemon_install` и `watchdog_install` |
| `.flow/shared/scripts/run.sh profile_init preflight --profile <name>` | финальная проверка и повторный rerun baseline | тот же profile/env, что и для install | `PREFLIGHT_READY=0|1`, `SMOKE_STEP`, `CHECKLIST` | health summary и smoke checklist |
| `.flow/shared/scripts/run.sh daemon_install ...` | не вызывается напрямую в штатном сценарии | нет | нет | остаётся внутренней деталью `profile_init install` |
| `.flow/shared/scripts/run.sh watchdog_install ...` | не вызывается напрямую в штатном сценарии | нет | нет | остаётся внутренней деталью `profile_init install` |

Принцип: визард может парсить только уже существующие стабильные маркеры stdout/stderr и не должен повторно реализовывать проверки branch existence, Project ID matching, auth readiness, state-layout creation или install semantics.

## Артефакты, которые визард создаёт или обновляет

### Всегда или почти всегда

- `.flow/tmp/wizard/flow-configurator-state.json`
- `.flow/config/flow.env`
- `.flow/config/flow.sample.env` через `profile_init init` или `apply_migration_kit`
- `.flow/state` и namespaced layout внутри host-level state root через `profile_init`
- `.flow/launchd` и связанные plist/install-links через `profile_init install`

### Условно

- `/.flow/shared` как submodule или snapshot bootstrap
- `.flow/config/root/github-actions.required-files.txt`
- `.flow/config/root/github-actions.required-secrets.txt`
- `.github/workflows/*.yml`
- `.github/pull_request_template.md`
- `.env` или `.env.deploy`, если пользователь подтверждает запись host-level `GH_APP_*`/`OPS_BOT_*` значений
- host-level runtime logs в `<AI_FLOW_ROOT_DIR>/logs/<profile>/runtime/*`
- backup-файлы визарда в `.flow/tmp/wizard/backups/<timestamp>/...` при overwrite-конфликтах

## Правила idempotency и safe-overwrite

1. `onboarding_audit` и `profile_init preflight` можно запускать на каждом старте визарда; они read-mostly и служат baseline-проверкой.
2. `profile_init install` считается допустимым idempotent rerun после любого подтверждённого изменения `flow.env`; визард не должен пытаться решать сам, нужен ли прямой `daemon_install`.
3. `profile_init init` нельзя запускать с `--force` без явного подтверждения overwrite существующего `flow.env`.
4. Если `flow.env` уже существует, non-empty пользовательские значения сильнее дефолтов визарда. Автодефолт может заменить существующее значение только после явного согласия пользователя.
5. Unknown keys в `flow.env`, `.env` и `.env.deploy`, которые не входят в матрицу визарда, должны сохраняться как есть.
6. Secret-значения считаются `sticky`: если секрет уже записан и пользователь не выбрал `replace`, визард не должен обнулять или перезаписывать его.
7. Для overlay-файлов из `apply_migration_kit` действует правило `preview -> confirm -> backup -> apply`.
8. Если discovery показывает partially configured project, визард не откатывает существующие артефакты назад в `fresh`-состояние. Он двигается только вперёд: `missing -> materialized`, `invalid -> corrected`, `stale -> reinstalled`.
9. Любой failed backend-step переводит визард в `failed`, но не очищает промежуточный state; следующий запуск должен уметь продолжить с discovery и предложить либо retry, либо edit answers.
10. Для `rerun_reconfigure` без фактических изменений итоговый путь должен быть `discover -> preflight -> done`, без повторной записи файлов.

## Поведение на частично настроенном проекте

Визард обязан классифицировать частичную конфигурацию по фактам, а не по одному признаку:

| Ситуация | Признак | Действие визарда |
| --- | --- | --- |
| Toolkit не подключён | нет `/.flow/shared/scripts/run.sh` | перейти в bootstrap |
| Toolkit есть, env нет | `onboarding_audit` сообщает `PROFILE_ENV_FILE=missing` | спросить `project_profile`, вызвать `profile_init init` |
| Env есть, но обязательные поля пустые | `CHECK_FAIL` по `PROJECT_*`, token или auth | спросить только missing/invalid поля, затем `install` + `preflight` |
| Env валиден, но runtime не установлен | `PREFLIGHT_READY=0` и `daemon_status/watchdog_status` не готовы | не пересобирать bootstrap, а перейти сразу к `profile_init install` |
| Runtime установлен, но пользователь меняет binding | есть diff по `GITHUB_REPO`, `PROJECT_*`, labels или state root | показать high-risk warning, сохранить backup, потом выполнить `install` + `preflight` |
| Конфиг полный и diff пустой | `PREFLIGHT_READY=1`, изменений нет | показать summary и завершиться без записи |

## Решения для следующей реализации

Эта спека фиксирует следующие решения для `ISSUE-378` и `ISSUE-379`:

1. Flow-конфигуратор остаётся thin orchestrator поверх `apply_migration_kit`, `profile_init`, `onboarding_audit`.
2. Основной runtime config живёт в `.flow/config/flow.env`; host-global `GH_APP_*` и `OPS_BOT_*` по умолчанию предпочтительно писать в `.env`/`.env.deploy`, но визард может использовать `flow.env` как override-слой.
3. Resume state хранится отдельно от daemon runtime: `.flow/tmp/wizard/flow-configurator-state.json`.
4. Direct calls к `daemon_install`/`watchdog_install` в штатном wizard path не нужны; используется только `profile_init install`.
5. Safe-overwrite обязателен для `flow.env`, `.env/.env.deploy` и repo overlay-файлов.
