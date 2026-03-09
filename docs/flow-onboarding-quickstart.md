# Flow Onboarding Quickstart

## Цель
Подключить flow-комплект `scripts/codex` к новому проекту так, чтобы:
- у проекта был свой локальный checkout;
- automation работала против его GitHub repo и его Project v2;
- repo/project-binding задавался через env/profile, без ручной правки bash-логики.

Этот документ — короткий onboarding для одного нового проекта.

Если нужен перенос двух проектов на одном хосте, multi-profile режим, rollback и extraction strategy, см. `docs/flow-portability-runbook.md`.
Если нужен отдельный onboarding GitHub App auth-сервиса, см. `docs/gh-app-daemon-integration-plan.md`.
Если нужен пошаговый чеклист без лишнего контекста, см. `docs/flow-onboarding-checklist.md`.

## Что считается результатом
После прохождения quickstart у вас есть:
- локальная папка проекта с каталогом `scripts/codex`;
- profile env-файл для этого проекта;
- работающий auth-сервис или настроенный fallback;
- установленный daemon/watchdog для нового profile;
- успешный smoke: `Todo -> In Progress -> Review/Done` на тестовой карточке.

## Что нужно подготовить заранее

### 1. Локальный контур
- локальная папка проекта, например `/Users/alex/sites/acme-app`;
- чистый git checkout нового проекта;
- доступные `bash`, `gh`, `jq`, `node`;
- `launchctl`, если daemon/watchdog будут запускаться как штатные launchd-агенты.

Примечание: текущий service-layer flow рассчитан на `launchd`. На Linux можно временно запускать `daemon_loop`/`watchdog_loop` вручную или адаптировать service-wrapper отдельно.

### 2. GitHub-контур
- новый repo, например `acme/acme-app`;
- рабочие ветки, обычно `main` и `development`;
- GitHub Project v2, который будет источником задач для daemon-flow;
- права на repo и Project v2;
- если Project user-owned, отдельный `DAEMON_GH_PROJECT_TOKEN`.

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

### Auth-режим
Рекомендуемый штатный вариант:
- GitHub App token для `Issue/PR`;
- `DAEMON_GH_PROJECT_TOKEN` для Project v2, если project user-owned.

Минимум для user-owned Project v2:
- `DAEMON_GH_PROJECT_TOKEN=<PAT>`
- scopes: `repo`, `read:project`, `project`

Подробно про GitHub App, permissions и hybrid mode: `docs/gh-app-daemon-integration-plan.md`.

## Что перенести в новый repo
Минимальный комплект:
- `scripts/codex`
- `docs/flow-onboarding-checklist.md`
- `docs/flow-onboarding-quickstart.md`
- `docs/flow-portability-runbook.md`
- `docs/gh-app-daemon-integration-plan.md`

Практическое правило:
- repo/project-specific значения хранятся в env;
- скрипты не переписываются под новый repo до тех пор, пока bootstrap не доказал, что текущая конфигурация уже работает.

## Bootstrap в локальной папке проекта

Пример:
- локальная папка: `/Users/alex/sites/acme-app`
- repo: `acme/acme-app`
- profile: `acme`

### Шаг 1. Открыть корень нового проекта
```bash
cd /Users/alex/sites/acme-app
```

### Шаг 2. Создать profile env и state-dir
```bash
scripts/codex/run.sh profile_init init --profile acme
```

Ожидаемый результат:
- создан `.tmp/codex/profiles/acme.env`
- создан `.tmp/codex/acme`

### Шаг 3. Заполнить env-файл
Открыть `.tmp/codex/profiles/acme.env` и задать минимум:

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

CODEX_STATE_DIR=/Users/alex/sites/acme-app/.tmp/codex/acme
FLOW_STATE_DIR=/Users/alex/sites/acme-app/.tmp/codex/acme

WATCHDOG_DAEMON_LABEL=com.planka.codex-daemon.acme
WATCHDOG_DAEMON_INTERVAL_SEC=45
```

Если auth-сервис пока не готов, временно допустим fallback:

```dotenv
DAEMON_GH_TOKEN_FALLBACK_ENABLED=1
DAEMON_GH_TOKEN=<fallback-pat>
```

Но это аварийный режим, не основной.

## Обязательная проверка env до install
```bash
scripts/codex/run.sh profile_init preflight --profile acme
```

Ожидается:
- `PREFLIGHT_READY=1`

Если нет, исправляйте `CHECK_FAIL ...` в `.tmp/codex/profiles/acme.env`, а не исходники `scripts/codex`.

## Поднять auth-сервис
Если используется GitHub App:

1. Проверить, что заданы:
   - `GH_APP_ID`
   - `GH_APP_INSTALLATION_ID`
   - `GH_APP_PRIVATE_KEY_PATH`
   - `GH_APP_INTERNAL_SECRET`
2. Запустить:

```bash
scripts/codex/run.sh gh_app_auth_pm2_start
scripts/codex/run.sh gh_app_auth_pm2_health
```

Если auth-сервис уже живёт на этом хосте и profile использует тот же `GH_APP_INTERNAL_SECRET`, достаточно health-check.

## Установить daemon/watchdog для нового profile
Штатный способ:

```bash
scripts/codex/run.sh profile_init install --profile acme
```

Что делает команда:
- валидирует env;
- ставит daemon для profile;
- ставит watchdog для profile;
- прокидывает нужный `DAEMON_GH_ENV_FILE` и отдельный `<state-dir>`.

Если нужен безопасный preview без изменений:

```bash
scripts/codex/run.sh profile_init bootstrap --profile acme --dry-run
```

## Smoke-check после install

### 1. API и auth
```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh github_health_check
```

### 2. Snapshot состояния
```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh status_snapshot
```

### 3. Статус daemon
```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh daemon_status com.planka.codex-daemon.acme
```

### 4. Статус watchdog
```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh watchdog_status com.planka.codex-watchdog.acme
```

### 5. Smoke на живой карточке
1. Создать тестовую карточку в новом Project v2.
2. Поставить `Status=Todo`.
3. Дождаться, что daemon переведет её в `In Progress`.
4. Убедиться, что:
   - claim произошёл в новом Project;
   - Issue/PR-операции идут в новый repo;
   - state/log/runtime пишутся в `.tmp/codex/acme`.
5. Довести цикл до `Review`/`Done` или откатить smoke-карточку вручную.

## Day-2 команды для нового проекта

### Повторная проверка
```bash
scripts/codex/run.sh profile_init preflight --profile acme
```

### Ручной запуск daemon/watchdog с явным env
```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh daemon_install com.planka.codex-daemon.acme 45
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme WATCHDOG_DAEMON_LABEL=com.planka.codex-daemon.acme WATCHDOG_DAEMON_INTERVAL_SEC=45 scripts/codex/run.sh watchdog_install com.planka.codex-watchdog.acme 45
```

### Остановка profile
```bash
scripts/codex/run.sh watchdog_uninstall com.planka.codex-watchdog.acme
scripts/codex/run.sh daemon_uninstall com.planka.codex-daemon.acme
```

## Что нельзя смешивать между проектами
- один и тот же `CODEX_STATE_DIR/FLOW_STATE_DIR` для двух repo;
- одни и те же daemon/watchdog labels;
- default project binding от PLANKA и non-default profile нового проекта;
- один и тот же `Project v2` для unrelated repos без явного решения;
- ручную правку repo/project binding внутри bash-скриптов вместо env/profile.

## Типовые ошибки

### `Non-default Project profile requires explicit PROJECT_ID, PROJECT_NUMBER and PROJECT_OWNER`
Причина:
- profile не `default`, но project-binding заполнен не полностью.

Что делать:
- заполнить все три переменные в `.tmp/codex/profiles/<profile>.env`.

### `Resource not accessible by integration`
Причина:
- GitHub App не имеет нужного доступа к Project v2;
- user-owned Project запущен без `DAEMON_GH_PROJECT_TOKEN`.

Что делать:
- проверить permissions App;
- обновить installation;
- для user-owned Project включить hybrid mode.

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
2. `.tmp/codex/profiles/<profile>.env` заполнен.
3. `profile_init preflight` даёт `PREFLIGHT_READY=1`.
4. auth-сервис healthy или fallback сознательно включен.
5. `profile_init install` завершился без ошибки.
6. `daemon_status` и `watchdog_status` показывают установленный profile.
7. smoke-карточка проходит хотя бы этап `Todo -> In Progress`.

## Куда смотреть дальше
- `docs/flow-portability-runbook.md` — multi-project, migration, rollback, extraction strategy.
- `docs/gh-app-daemon-integration-plan.md` — GitHub App permissions, hybrid mode, auth-service onboarding.
- `docs/flow-toolkit-packaging.md` — что переносить в consumer-project и как выносить toolkit в отдельный repo.
- `scripts/codex/README.md` — каталог команд и env-справочник.
