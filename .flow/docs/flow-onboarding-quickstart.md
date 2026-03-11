# Flow Onboarding Quickstart

## Цель
Подключить flow-комплект `.flow/` к новому проекту так, чтобы:
- у проекта был свой локальный checkout;
- automation работала против его GitHub repo и его Project v2;
- repo/project-binding задавался через env/profile, без ручной правки bash-логики.

Этот документ — короткий onboarding для одного нового проекта.

Если нужен перенос двух проектов на одном хосте, multi-profile режим, rollback и extraction strategy, см. `.flow/docs/flow-portability-runbook.md`.
Если нужен отдельный onboarding GitHub App auth-сервиса, см. `.flow/docs/gh-app-daemon-integration-plan.md`.
Если нужен help по repo Actions secrets, см. `.flow/docs/github-actions-repo-secrets.md`.
Если нужен пошаговый чеклист без лишнего контекста, см. `.flow/docs/flow-onboarding-checklist.md`.

## Что считается результатом
После прохождения quickstart у вас есть:
- локальная папка проекта с каталогом `.flow/scripts`;
- восстановленный repo automation overlay в `.github/workflows/` и `.github/pull_request_template.md`, если он нужен этому consumer-project;
- единый flow env-файл для этого проекта;
- работающий auth-сервис или настроенный fallback;
- установленный daemon/watchdog для нового profile;
- канонические `launchd` plist в `.flow/launchd/` и install-links в `~/Library/LaunchAgents/`;
- временные toolkit-артефакты в `.flow/tmp/`;
- manifest обязательных repo Actions secrets в `.flow/config/root/github-actions.required-secrets.txt`;
- успешный smoke: `Todo -> In Progress -> Review/Done` на тестовой карточке.

## Что нужно подготовить заранее

### 1. Локальный контур
- локальная папка проекта, например `<HOME>/sites/acme-app`;
- чистый git checkout нового проекта;
- доступные `bash`, `gh`, `jq`, `node`;
- `launchctl`, если daemon/watchdog будут запускаться как штатные launchd-агенты.

Примечание: текущий service-layer flow рассчитан на `launchd`. На Linux можно временно запускать `daemon_loop`/`watchdog_loop` вручную или адаптировать service-wrapper отдельно.

### 2. GitHub-контур
- новый repo, например `acme/acme-app`;
- рабочие ветки, обычно `main` и `development`;
- GitHub Project v2, который будет источником задач для daemon-flow;
- права на repo и Project v2;
- отдельный `DAEMON_GH_PROJECT_TOKEN` для Project v2 операций текущего flow.

### 3. Значения, которые надо знать до bootstrap
- `GITHUB_REPO=<owner>/<repo>`;
- `FLOW_BASE_BRANCH=main`;
- `FLOW_HEAD_BRANCH=development`;
- `PROJECT_ID=<project-node-id>`;
- `PROJECT_NUMBER=<project-number>`;
- `PROJECT_OWNER=<@me|org-login>`;
- `PROJECT_PROFILE=<slug>`, например `acme`.

## Минимальный GitHub checklist

### Repo
1. Создать repo.
2. Подготовить базовые ветки:
   - `main`
   - `development`
3. Убедиться, что `gh auth status` работает под нужным аккаунтом.

### Project v2
1. Создать или выбрать Project v2 для нового проекта.
2. Зафиксировать:
   - `PROJECT_ID`
   - `PROJECT_NUMBER`
   - `PROJECT_OWNER`
3. Убедиться, что automation сможет читать и менять `Status/Flow`.

Где это брать в GitHub UI:
- `PROJECT_NUMBER`: из URL открытого Project v2, например `github.com/users/<owner>/projects/<number>` или `github.com/orgs/<owner>/projects/<number>`
- `PROJECT_OWNER`: из того же URL, это `<owner>` после `/users/` или `/orgs/`
- `PROJECT_ID`: обычный GitHub UI node id проекта не показывает; owner/number берутся из UI, а сам `PROJECT_ID` нужно получить отдельно через `gh project view <number> --owner <owner> --format json` или GraphQL/API

Готовый запрос, который сразу показывает owner, title, number и id всех проектов owner:
```bash
gh project list --owner <PROJECT_OWNER> --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'
```

Готовая команда для `PROJECT_ID`:
```bash
gh project view <PROJECT_NUMBER> --owner <PROJECT_OWNER> --format json --jq '.id'
```

### Auth-режим
Рекомендуемый штатный вариант:
- GitHub App token для `Issue/PR`;
- `DAEMON_GH_PROJECT_TOKEN` для Project v2 операций.

Обязательный минимум для рабочего profile:
- `DAEMON_GH_PROJECT_TOKEN=<PAT>`
- scopes: `repo`, `read:project`, `project`

Рекомендуемые дополнительные scopes:
- `read:org` — полезен, если project/repo живут в org-контуре или `gh` должен стабильно видеть owner/membership без сюрпризов прав.
- `read:discussions` — безопасный read-only scope на случай repo с включёнными Discussions и чтобы не упираться в under-scoped PAT при расширении automation вокруг repo metadata.

Где выпустить `DAEMON_GH_PROJECT_TOKEN` в GitHub UI:
- avatar -> `Settings`
- `Developer settings`
- `Personal access tokens`
- `Tokens (classic)`
- `Generate new token`

Опционально, только как аварийный fallback при недоступности auth-сервиса:
- `DAEMON_GH_TOKEN=<PAT>`
- `DAEMON_GH_TOKEN_FALLBACK_ENABLED=1`

Подробно про GitHub App, permissions и hybrid mode: `.flow/docs/gh-app-daemon-integration-plan.md`.

## Что перенести в новый repo
Минимальный комплект:
- `.flow/`
- `.flow/docs/flow-onboarding-checklist.md`
- `.flow/docs/flow-onboarding-quickstart.md`
- `.flow/docs/flow-portability-runbook.md`
- `.flow/docs/gh-app-daemon-integration-plan.md`
- `COMMAND_TEMPLATES.md`

Практическое правило:
- repo/project-specific значения хранятся в env;
- скрипты не переписываются под новый repo до тех пор, пока bootstrap не доказал, что текущая конфигурация уже работает.
- `.tmp/codex/` больше не считается runtime-каталогом; это только legacy compatibility layer поверх `.flow/`.
- repo-level GitHub workflows не являются ядром toolkit, но migration kit может переносить их как overlay исходного consumer-project вместе с manifest required secrets.

Если нужно перенести комплект без ручной выборки файлов, можно собрать архив:
- в текущем проекте: `.flow/scripts/run.sh create_migration_kit --project acme`
- в новом проекте после распаковки: `.flow/scripts/run.sh apply_migration_kit --project acme`
- archive положит безопасный шаблон `.flow/config/flow.sample.env` без копирования живых токенов из исходного проекта
- archive также положит `.flow/templates/github/` как source overlay для `.github/workflows/` и `.github/pull_request_template.md`
- `apply_migration_kit` развернёт этот overlay в новый repo и оставит manifest required secrets в `.flow/config/root/github-actions.required-secrets.txt`

## Bootstrap в локальной папке проекта

Пример:
- локальная папка: `<HOME>/sites/acme-app`
- repo: `acme/acme-app`
- profile: `acme`

### Шаг 1. Открыть корень нового проекта
```bash
cd <HOME>/sites/acme-app
```

### Шаг 2. Выполнить первичный аудит consumer-project
```bash
.flow/scripts/run.sh onboarding_audit
```

Скрипт проверит:
- перенесён ли toolkit;
- хватает ли локальных команд (`git`, `gh`, `jq`, `node`, ...);
- есть ли git-репозиторий, `origin`, ветки `main` и `development`;
- авторизован ли `gh`.

Если дальше нужен полный audit profile/env, запуск повторяется с `--profile`.

Если toolkit переносился через `migration_kit.tgz`, перед audit сначала выполни:
```bash
.flow/scripts/run.sh apply_migration_kit --project acme
```

После этого ожидается:
- создан `.flow/config/flow.sample.env`
- создан `.flow/config/flow.env`
- созданы `.flow/config/root/github-actions.required-files.txt` и `.flow/config/root/github-actions.required-secrets.txt`
- развернуты `.github/workflows/*.yml` и, если он был в source-kit, `.github/pull_request_template.md`
- создан `.flow/state/codex/acme`

### Шаг 3. Создать flow env и state-dir
```bash
.flow/scripts/run.sh profile_init init --profile acme
```

Ожидаемый результат:
- создан `.flow/config/flow.env`
- создан `.flow/state/codex/acme`

Если перед этим уже был выполнен `apply_migration_kit`, шаг можно пропустить: рабочий `.flow/config/flow.env` уже материализован из `.flow/config/flow.sample.env`.

### Шаг 4. Проверить, что именно осталось настроить в flow env
```bash
.flow/scripts/run.sh onboarding_audit --profile acme
```

### Шаг 5. Заполнить env-файл
Открыть `.flow/config/flow.env` и задать минимум:

```dotenv
PROJECT_PROFILE=acme
GITHUB_REPO=acme/acme-app
FLOW_BASE_BRANCH=main
FLOW_HEAD_BRANCH=development

PROJECT_ID=<project-node-id>
PROJECT_NUMBER=<project-number>
PROJECT_OWNER=@me

DAEMON_GH_PROJECT_TOKEN=<pat-for-project-v2>
GH_APP_INTERNAL_SECRET=<shared-secret>

GH_APP_BIND=127.0.0.1
GH_APP_PORT=8787

CODEX_STATE_DIR=<HOME>/sites/acme-app/.flow/state/codex/acme
FLOW_STATE_DIR=<HOME>/sites/acme-app/.flow/state/codex/acme

WATCHDOG_DAEMON_LABEL=com.flow.codex-daemon.acme
WATCHDOG_DAEMON_INTERVAL_SEC=45
```

Опционально можно явно зафиксировать namespace labels:

```dotenv
FLOW_LAUNCHD_NAMESPACE=com.flow
```

Если переменная не задана, это и так дефолт.

Если auth-сервис пока не готов или нужен аварийный режим, можно временно включить fallback:

```dotenv
DAEMON_GH_TOKEN_FALLBACK_ENABLED=1
DAEMON_GH_TOKEN=<fallback-pat>
```

Но это аварийный режим, не основной. Для штатного flow `DAEMON_GH_PROJECT_TOKEN` всё равно должен быть заполнен.

Если consumer-project использует auth-service, ops-bot или remote push, эти переменные тоже нужно заполнить прямо в `.flow/config/flow.env`:
- `GH_APP_ID`
- `GH_APP_INSTALLATION_ID`
- `GH_APP_PRIVATE_KEY_PATH` — рекомендуемо хранить как `<HOME>/.secrets/gh-apps/codex-flow.private-key.pem`
- `GH_APP_INTERNAL_SECRET`
- `GH_APP_OWNER`
- `GH_APP_REPO`
- `GH_APP_BIND`
- `GH_APP_PORT`
- `GH_APP_TOKEN_SKEW_SEC`
- `DAEMON_GH_AUTH_TIMEOUT_SEC`
- `DAEMON_GH_AUTH_TOKEN_URL`

Отдельно по repo Actions:
- открыть `.flow/config/root/github-actions.required-secrets.txt`
- при необходимости свериться с `.flow/docs/github-actions-repo-secrets.md`, чтобы понять, что вписывать в каждый secret
- в GitHub UI нового repo перейти `Settings -> Secrets and variables -> Actions`
- вручную создать все secrets из списка
- если deploy workflow использует `runs-on: [self-hosted, <label>]`, отдельно зарегистрировать online self-hosted runner именно для нового repo в `Settings -> Actions -> Runners`
- затем повторно прогнать `.flow/scripts/run.sh onboarding_audit --profile acme`, чтобы audit проверил repo workflow overlay и наличие secrets через GitHub API

## Обязательная проверка env до install
```bash
.flow/scripts/run.sh profile_init preflight --profile acme
```

Ожидается:
- `PREFLIGHT_READY=1`

Если нет, исправляйте `CHECK_FAIL ...` в `.flow/config/flow.env`, а не исходники `.flow/scripts`.

## Поднять auth-сервис
Если используется GitHub App:

1. Проверить, что заданы:
   - `GH_APP_ID`
   - `GH_APP_INSTALLATION_ID`
   - `GH_APP_PRIVATE_KEY_PATH` (рекомендуемый путь: `<HOME>/.secrets/gh-apps/codex-flow.private-key.pem`)
   - `GH_APP_INTERNAL_SECRET`
2. Запустить:

```bash
.flow/scripts/run.sh gh_app_auth_pm2_start
.flow/scripts/run.sh gh_app_auth_pm2_health
```

Если auth-сервис уже живёт на этом хосте и profile использует тот же `GH_APP_INTERNAL_SECRET`, достаточно health-check.

## Установить daemon/watchdog для нового profile
Штатный способ:

```bash
.flow/scripts/run.sh profile_init install --profile acme
```

Что делает команда:
- валидирует env;
- ставит daemon для profile;
- ставит watchdog для profile;
- прокидывает нужный `DAEMON_GH_ENV_FILE` и отдельный `<state-dir>`.

Если нужен безопасный preview без изменений:

```bash
.flow/scripts/run.sh profile_init bootstrap --profile acme --dry-run
```

## Smoke-check после install

### 1. API и auth
```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/scripts/run.sh github_health_check
```

### 2. Snapshot состояния
```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/scripts/run.sh status_snapshot
```

### 3. Статус daemon
```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/scripts/run.sh daemon_status com.flow.codex-daemon.acme
```

### 4. Статус watchdog
```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/scripts/run.sh watchdog_status com.flow.codex-watchdog.acme
```

### 5. Smoke на живой карточке
1. Создать тестовую карточку в новом Project v2.
2. Поставить `Status=Todo`.
3. Дождаться, что daemon переведет её в `In Progress`.
4. Убедиться, что:
   - claim произошёл в новом Project;
   - Issue/PR-операции идут в новый repo;
   - state/log/runtime пишутся в `.flow/state/codex/acme`.
5. Довести цикл до `Review`/`Done` или откатить smoke-карточку вручную.

## Day-2 команды для нового проекта

### Повторная проверка
```bash
.flow/scripts/run.sh profile_init preflight --profile acme
```

### Ручной запуск daemon/watchdog с явным env
```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/scripts/run.sh daemon_install com.flow.codex-daemon.acme 45
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme WATCHDOG_DAEMON_LABEL=com.flow.codex-daemon.acme WATCHDOG_DAEMON_INTERVAL_SEC=45 .flow/scripts/run.sh watchdog_install com.flow.codex-watchdog.acme 45
```

Что создаётся при install:
- канонический plist: `.flow/launchd/<label>.plist`
- install-link для `launchd`: `~/Library/LaunchAgents/<label>.plist`

### Остановка profile
```bash
.flow/scripts/run.sh watchdog_uninstall com.flow.codex-watchdog.acme
.flow/scripts/run.sh daemon_uninstall com.flow.codex-daemon.acme
```

## Что нельзя смешивать между проектами
- один и тот же `CODEX_STATE_DIR/FLOW_STATE_DIR` для двух repo;
- одни и те же daemon/watchdog labels;
- default project binding текущего consumer-project и non-default profile нового проекта;
- один и тот же `Project v2` для unrelated repos без явного решения;
- ручную правку repo/project binding внутри bash-скриптов вместо env/profile.

## Типовые ошибки

### `Non-default Project profile requires explicit PROJECT_ID, PROJECT_NUMBER and PROJECT_OWNER`
Причина:
- profile не `default`, но project-binding заполнен не полностью.

Что делать:
- заполнить все три переменные в `.flow/config/flow.env`.

### `Resource not accessible by integration`
Причина:
- GitHub App не имеет нужного доступа к Project v2;
- не задан `DAEMON_GH_PROJECT_TOKEN` для Project v2 операций текущего flow.

Что делать:
- проверить permissions App;
- обновить installation;
- заполнить `DAEMON_GH_PROJECT_TOKEN`.

### `PREFLIGHT_READY=0`
Причина:
- не заполнен обязательный env;
- нет `GH_APP_INTERNAL_SECRET`;
- profile/env-file перепутаны.

Что делать:
- исправить env-файл;
- повторить `profile_init preflight --profile <profile>`.

### Snapshot/logs пишутся “не туда”
Причина:
- не задан `DAEMON_GH_ENV_FILE`;
- state-dir не совпадает с profile.

Что делать:
- запускать команды с явным префиксом `env DAEMON_GH_ENV_FILE=... CODEX_STATE_DIR=... FLOW_STATE_DIR=...`.

### Dirty worktree блокирует flow
Причина:
- в repo есть незакоммиченные tracked changes.

Что делать:
- очистить tracked changes или отделить их в другую ветку/дельту до запуска smoke.

## Минимальный cutover checklist
1. `profile_init init` выполнен.
2. `.flow/config/flow.env` заполнен.
3. `profile_init preflight` даёт `PREFLIGHT_READY=1`.
4. auth-сервис healthy или fallback сознательно включен.
5. `profile_init install` завершился без ошибки.
6. `daemon_status` и `watchdog_status` показывают установленный profile.
7. smoke-карточка проходит хотя бы этап `Todo -> In Progress`.

## Куда смотреть дальше
- `.flow/docs/flow-portability-runbook.md` — multi-project, migration, rollback, extraction strategy.
- `.flow/docs/gh-app-daemon-integration-plan.md` — GitHub App permissions, hybrid mode, auth-service onboarding.
- `.flow/docs/flow-toolkit-packaging.md` — что переносить в consumer-project и как выносить toolkit в отдельный repo.
- `.flow/scripts/README.md` — каталог команд и env-справочник.
