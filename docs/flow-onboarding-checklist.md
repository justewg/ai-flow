# Flow Onboarding Checklist

> Канонический shared-toolkit path: `.flow/shared/{scripts,docs}`.

## Формат
Это чеклистовый companion к `.flow/shared/docs/flow-onboarding-quickstart.md`.

Используйте его, когда нужно быстро пройти онбординг нового проекта по шагам:
- создай это;
- возьми значения отсюда;
- пропиши сюда;
- проверь вот это.

Если нужен контекст, пояснения и troubleshooting, переключайтесь на `.flow/shared/docs/flow-onboarding-quickstart.md` и `.flow/shared/docs/flow-portability-runbook.md`.
Для расшифровки repo Actions secrets используйте `.flow/shared/docs/github-actions-repo-secrets.md`.

## 0. Что должно уже существовать
- [ ] Локальная папка проекта создана.
- [ ] Новый GitHub repo создан.
- [ ] В repo есть ветки `main` и `development`.
- [ ] Для проекта создан GitHub Project v2.
- [ ] Локально доступны `bash`, `gh`, `jq`, `node`.
- [ ] В новый repo уже перенесён automation-комплект.

Минимум, что нужно перенести:
- [ ] `.flow/shared/scripts/`
- [ ] `.flow/shared/docs/flow-onboarding-checklist.md`
- [ ] `.flow/shared/docs/flow-onboarding-quickstart.md`
- [ ] `.flow/shared/docs/flow-portability-runbook.md`
- [ ] `.flow/shared/docs/gh-app-daemon-integration-plan.md`
- [ ] `COMMAND_TEMPLATES.md`
- [ ] Если нужен полный repo automation overlay, подготовлены `.github/workflows/` и `.github/pull_request_template.md`

Опционально вместо ручного копирования:
- [ ] В текущем проекте выполнен `.flow/shared/scripts/run.sh create_migration_kit --project acme`
- [ ] Archive лежит в `.flow/migration/acme-migration-kit.tgz` или уже автоматически скопирован в `<target-repo>/.flow/migration/acme-migration-kit.tgz`
- [ ] Archive перенесён в новый repo и распакован в корне
- [ ] После распаковки выполнен `.flow/shared/scripts/run.sh apply_migration_kit --project acme`
- [ ] Проверено, что после `apply_migration_kit` появились `.flow/config/flow.sample.env` и `.flow/config/flow.env`
- [ ] Проверено, что после `apply_migration_kit` появились `.flow/templates/github/required-files.txt` и `.flow/templates/github/required-secrets.txt`
- [ ] Проверено, что `apply_migration_kit` развернул `.github/workflows/*.yml` и `.github/pull_request_template.md` из source overlay
- [ ] Понимание зафиксировано: `.tmp/codex/` больше не runtime-источник, а только legacy compatibility layer.

## 1. Собери входные значения

### Из GitHub repo
- [ ] Запиши `GITHUB_REPO=<owner>/<repo>`.
- [ ] Подтверди базовые ветки:
  - [ ] `FLOW_BASE_BRANCH=main`
  - [ ] `FLOW_HEAD_BRANCH=development`
- [ ] Открой `Settings -> Secrets and variables -> Actions` в новом repo: туда позже будут заведены repo Actions secrets.

### Из GitHub Project v2
- [ ] Запиши `PROJECT_ID`.
- [ ] Запиши `PROJECT_NUMBER`.
- [ ] Запиши `PROJECT_OWNER`.
- [ ] `PROJECT_NUMBER` и `PROJECT_OWNER` сняты из URL Project v2 в GitHub UI.
- [ ] При необходимости список проектов owner получен так: `gh project list --owner <PROJECT_OWNER> --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'`
- [ ] Для `PROJECT_ID` учтено, что GitHub UI его не показывает; он получен отдельно через `gh project view <number> --owner <owner> --format json` или API.
- [ ] Для `PROJECT_ID` при необходимости использована точная команда: `gh project view <PROJECT_NUMBER> --owner <PROJECT_OWNER> --format json --jq '.id'`

### Для profile
- [ ] Выбери `PROJECT_PROFILE`, например `acme`.
- [ ] Подтверди будущий state-dir, например `.flow/state/codex/acme`.
- [ ] Подтверди будущий log-dir, по умолчанию `<sites-root>/.ai-flow/logs/acme`.
- [ ] При необходимости зафиксируй namespace launchd labels: `FLOW_LAUNCHD_NAMESPACE=com.flow` (это же дефолт).

### Для auth
- [ ] Выпущен `DAEMON_GH_PROJECT_TOKEN` для Project v2 операций.
- [ ] PAT выпущен в GitHub UI: `Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token`.
- [ ] Для `DAEMON_GH_PROJECT_TOKEN` выданы базовые scopes: `repo`, `read:project`, `project`.
- [ ] При необходимости для совместимости добавлены `read:org` и `read:discussions`.
- [ ] Если используется GitHub App — готовы:
  - [ ] `GH_APP_ID`
  - [ ] `GH_APP_INSTALLATION_ID`
  - [ ] `GH_APP_PRIVATE_KEY_PATH`
  - [ ] `GH_APP_INTERNAL_SECRET`
- [ ] Если нужен аварийный fallback при недоступности auth-сервиса — осознанно включён fallback:
  - [ ] `DAEMON_GH_TOKEN_FALLBACK_ENABLED=1`
  - [ ] `DAEMON_GH_TOKEN=<PAT>`

### Для repo Actions overlay
- [ ] Понято, какие workflow из source-project нужны новому consumer-project без изменений, а какие потребуют ручной адаптации.
- [ ] Подготовлен список required repo secrets из `.flow/templates/github/required-secrets.txt`.
- [ ] Для каждого required secret есть понимание значения по `.flow/shared/docs/github-actions-repo-secrets.md`.
- [ ] Зафиксировано, что migration kit не переносит значения repo secrets; их нужно создавать вручную в GitHub UI.
- [ ] Если deploy workflow ждёт `runs-on: [self-hosted, <label>]`, зарегистрирован online self-hosted runner именно для нового repo или на уровне org.

## 2. Создай profile-файлы
- [ ] Перейди в корень нового проекта.

```bash
cd /path/to/new-project
```

- [ ] Запусти первичный аудит consumer-project.

```bash
.flow/shared/scripts/run.sh onboarding_audit
```

- [ ] Создай env-template и state-dir.

```bash
.flow/shared/scripts/run.sh profile_init init --profile acme
```

- [ ] Если уже использован `migration_kit.tgz`, этот шаг можно пропустить: `apply_migration_kit` сам создаёт рабочий `.flow/config/flow.env` из `.flow/config/flow.sample.env`.

- [ ] Убедись, что появились:
  - [ ] `.flow/config/flow.sample.env`
  - [ ] `.flow/config/flow.env`
  - [ ] `.flow/state/codex/acme`
  - [ ] `<sites-root>/.ai-flow/logs/acme` или явный `FLOW_LOGS_DIR`
  - [ ] `.flow/templates/github/required-files.txt`
  - [ ] `.flow/templates/github/required-secrets.txt`
  - [ ] `.github/workflows/*.yml`

- [ ] Запусти аудит profile/env.

```bash
.flow/shared/scripts/run.sh onboarding_audit --profile acme
```

- [ ] Для repo overlay исправлены `REPO_ACTION_FILE` и `GH_REPO_ACTIONS_SECRETS`, если audit их показал.
- [ ] Для deploy overlay исправлен `GH_REPO_SELF_HOSTED_RUNNER`, если audit показал отсутствие online runner.

## 3. Заполни env-файл
- [ ] Запусти интерактивный wizard:

```bash
.flow/shared/scripts/run.sh flow_configurator questionnaire --profile acme
```

- [ ] Проверь preview diff и подтверди запись только если wizard показывает ожидаемые изменения.
- [ ] При необходимости открой `.flow/config/flow.env` вручную и проверь, что минимум заполнен:
  - [ ] `PROJECT_PROFILE=acme`
  - [ ] `GITHUB_REPO=<owner>/<repo>`
  - [ ] `FLOW_BASE_BRANCH=main`
  - [ ] `FLOW_HEAD_BRANCH=development`
  - [ ] `PROJECT_ID=<...>`
  - [ ] `PROJECT_NUMBER=<...>`
  - [ ] `PROJECT_OWNER=<...>`
  - [ ] `DAEMON_GH_PROJECT_TOKEN=<...>` обязательно
  - [ ] `GH_APP_INTERNAL_SECRET=<...>` или fallback-пару
  - [ ] `CODEX_STATE_DIR=<root>/.flow/state/codex/acme`
  - [ ] `FLOW_STATE_DIR=<root>/.flow/state/codex/acme`
  - [ ] `WATCHDOG_DAEMON_LABEL=com.flow.codex-daemon.acme`
  - [ ] `WATCHDOG_DAEMON_INTERVAL_SEC=45`
- [ ] Убедись, что дополнительные flow-переменные тоже заполнены прямо в `.flow/config/flow.env`:
  - [ ] `GH_APP_ID`
  - [ ] `GH_APP_INSTALLATION_ID`
  - [ ] `GH_APP_PRIVATE_KEY_PATH` (рекомендуемо `<HOME>/.secrets/gh-apps/codex-flow.private-key.pem`)
  - [ ] `GH_APP_INTERNAL_SECRET`
  - [ ] `GH_APP_OWNER`
  - [ ] `GH_APP_REPO`
  - [ ] `GH_APP_BIND`
  - [ ] `GH_APP_PORT`
  - [ ] `GH_APP_TOKEN_SKEW_SEC`
  - [ ] `DAEMON_GH_AUTH_TIMEOUT_SEC`
  - [ ] `DAEMON_GH_AUTH_TOKEN_URL`
- [ ] Если в repo используются workflow из migration kit, вручную созданы все secrets из `.flow/templates/github/required-secrets.txt` через `Settings -> Secrets and variables -> Actions`.

## 4. Проверь preflight
- [ ] Запусти:

```bash
.flow/shared/scripts/run.sh profile_init preflight --profile acme
```

- [ ] Убедись, что есть `PREFLIGHT_READY=1`.
- [ ] Если есть `CHECK_FAIL`, исправляй env, а не скрипты.

## 5. Подними auth

### Вариант A: GitHub App
- [ ] Запусти auth-service:

```bash
.flow/shared/scripts/run.sh gh_app_auth_pm2_start
.flow/shared/scripts/run.sh gh_app_auth_pm2_health
```

- [ ] Убедись, что health-check зелёный.

### Вариант B: Fallback
- [ ] Убедись, что fallback включён сознательно и `DAEMON_GH_TOKEN` прописан в env как аварийный PAT.

## 6. Установи automation
- [ ] Выполни:

```bash
.flow/shared/scripts/run.sh profile_init install --profile acme
```

- [ ] Если хочешь сначала только preview — используй:

```bash
.flow/shared/scripts/run.sh profile_init bootstrap --profile acme --dry-run
```

## 7. Проверь runtime
- [ ] Проверка GitHub API:

```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/shared/scripts/run.sh github_health_check
```

- [ ] Проверка snapshot:

```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/shared/scripts/run.sh status_snapshot
```

- [ ] Проверка daemon:

```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/shared/scripts/run.sh daemon_status com.flow.codex-daemon.acme
```

- [ ] Проверка watchdog:

```bash
env DAEMON_GH_ENV_FILE=.flow/config/flow.env CODEX_STATE_DIR=.flow/state/codex/acme FLOW_STATE_DIR=.flow/state/codex/acme .flow/shared/scripts/run.sh watchdog_status com.flow.codex-watchdog.acme
```

## 8. Сделай smoke на живой карточке
- [ ] Создай тестовую карточку в новом Project v2.
- [ ] Поставь `Status=Todo`.
- [ ] Дождись claim в `In Progress`.
- [ ] Проверь:
  - [ ] статус меняется в нужном Project;
  - [ ] действия идут в нужный repo;
  - [ ] state пишется в `.flow/state/codex/acme`;
  - [ ] логи не смешиваются с другим проектом.
- [ ] Доведи smoke до `Review/Done` или откати карточку вручную.

## 9. Cutover done, если всё ниже true
- [ ] `profile_init preflight` зелёный.
- [ ] auth healthy или fallback включён осознанно.
- [ ] daemon установлен.
- [ ] watchdog установлен.
- [ ] smoke-карточка прошла `Todo -> In Progress`.
- [ ] новый проект не пишет state/logs в чужой profile.

## 10. Если надо откатить
- [ ] Останови watchdog:

```bash
.flow/shared/scripts/run.sh watchdog_uninstall com.flow.codex-watchdog.acme
```

- [ ] Останови daemon:

```bash
.flow/shared/scripts/run.sh daemon_uninstall com.flow.codex-daemon.acme
```

- [ ] Сохрани `.flow/state/codex/acme`.
- [ ] Исправь `.flow/config/flow.env`.
- [ ] Повтори preflight/install.

## Куда смотреть дальше
- `.flow/shared/docs/flow-onboarding-quickstart.md`
- `.flow/shared/docs/flow-portability-runbook.md`
- `.flow/shared/docs/gh-app-daemon-integration-plan.md`
- `.flow/shared/docs/flow-toolkit-packaging.md`
