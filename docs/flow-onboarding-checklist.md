# Flow Onboarding Checklist

## Формат
Это чеклистовый companion к `docs/flow-onboarding-quickstart.md`.

Используйте его, когда нужно быстро пройти онбординг нового проекта по шагам:
- создай это;
- возьми значения отсюда;
- пропиши сюда;
- проверь вот это.

Если нужен контекст, пояснения и troubleshooting, переключайтесь на `docs/flow-onboarding-quickstart.md` и `docs/flow-portability-runbook.md`.

## 0. Что должно уже существовать
- [ ] Локальная папка проекта создана.
- [ ] Новый GitHub repo создан.
- [ ] В repo есть ветки `main` и `development`.
- [ ] Для проекта создан GitHub Project v2.
- [ ] Локально доступны `bash`, `gh`, `jq`, `node`.
- [ ] В новый repo уже перенесён automation-комплект.

Минимум, что нужно перенести:
- [ ] `scripts/codex/`
- [ ] `docs/flow-onboarding-checklist.md`
- [ ] `docs/flow-onboarding-quickstart.md`
- [ ] `docs/flow-portability-runbook.md`
- [ ] `docs/gh-app-daemon-integration-plan.md`

## 1. Собери входные значения

### Из GitHub repo
- [ ] Запиши `GITHUB_REPO=<owner>/<repo>`.
- [ ] Подтверди базовые ветки:
  - [ ] `FLOW_BASE_BRANCH=main`
  - [ ] `FLOW_HEAD_BRANCH=development`

### Из GitHub Project v2
- [ ] Запиши `PROJECT_ID`.
- [ ] Запиши `PROJECT_NUMBER`.
- [ ] Запиши `PROJECT_OWNER`.

### Для profile
- [ ] Выбери `PROJECT_PROFILE`, например `acme`.
- [ ] Подтверди будущий state-dir, например `.tmp/codex/acme`.

### Для auth
- [ ] Если project user-owned — выпущен `DAEMON_GH_PROJECT_TOKEN`.
- [ ] Если используется GitHub App — готовы:
  - [ ] `GH_APP_ID`
  - [ ] `GH_APP_INSTALLATION_ID`
  - [ ] `GH_APP_PRIVATE_KEY_PATH`
  - [ ] `GH_APP_INTERNAL_SECRET`
- [ ] Если GitHub App пока не готов — осознанно включён fallback:
  - [ ] `DAEMON_GH_TOKEN_FALLBACK_ENABLED=1`
  - [ ] `DAEMON_GH_TOKEN=<PAT>`

## 2. Создай profile-файлы
- [ ] Перейди в корень нового проекта.

```bash
cd /path/to/new-project
```

- [ ] Создай env-template и state-dir.

```bash
scripts/codex/run.sh profile_init init --profile acme
```

- [ ] Убедись, что появились:
  - [ ] `.tmp/codex/profiles/acme.env`
  - [ ] `.tmp/codex/acme`

## 3. Заполни env-файл
- [ ] Открой `.tmp/codex/profiles/acme.env`.
- [ ] Пропиши:
  - [ ] `PROJECT_PROFILE=acme`
  - [ ] `GITHUB_REPO=<owner>/<repo>`
  - [ ] `FLOW_BASE_BRANCH=main`
  - [ ] `FLOW_HEAD_BRANCH=development`
  - [ ] `PROJECT_ID=<...>`
  - [ ] `PROJECT_NUMBER=<...>`
  - [ ] `PROJECT_OWNER=<...>`
  - [ ] `DAEMON_GH_PROJECT_TOKEN=<...>` при user-owned Project
  - [ ] `GH_APP_INTERNAL_SECRET=<...>` или fallback-пару
  - [ ] `CODEX_STATE_DIR=<root>/.tmp/codex/acme`
  - [ ] `FLOW_STATE_DIR=<root>/.tmp/codex/acme`
  - [ ] `WATCHDOG_DAEMON_LABEL=com.planka.codex-daemon.acme`
  - [ ] `WATCHDOG_DAEMON_INTERVAL_SEC=45`

## 4. Проверь preflight
- [ ] Запусти:

```bash
scripts/codex/run.sh profile_init preflight --profile acme
```

- [ ] Убедись, что есть `PREFLIGHT_READY=1`.
- [ ] Если есть `CHECK_FAIL`, исправляй env, а не скрипты.

## 5. Подними auth

### Вариант A: GitHub App
- [ ] Запусти auth-service:

```bash
scripts/codex/run.sh gh_app_auth_pm2_start
scripts/codex/run.sh gh_app_auth_pm2_health
```

- [ ] Убедись, что health-check зелёный.

### Вариант B: Fallback
- [ ] Убедись, что fallback включён сознательно и PAT прописан в env.

## 6. Установи automation
- [ ] Выполни:

```bash
scripts/codex/run.sh profile_init install --profile acme
```

- [ ] Если хочешь сначала только preview — используй:

```bash
scripts/codex/run.sh profile_init bootstrap --profile acme --dry-run
```

## 7. Проверь runtime
- [ ] Проверка GitHub API:

```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh github_health_check
```

- [ ] Проверка snapshot:

```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh status_snapshot
```

- [ ] Проверка daemon:

```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh daemon_status com.planka.codex-daemon.acme
```

- [ ] Проверка watchdog:

```bash
env DAEMON_GH_ENV_FILE=.tmp/codex/profiles/acme.env CODEX_STATE_DIR=.tmp/codex/acme FLOW_STATE_DIR=.tmp/codex/acme scripts/codex/run.sh watchdog_status com.planka.codex-watchdog.acme
```

## 8. Сделай smoke на живой карточке
- [ ] Создай тестовую карточку в новом Project v2.
- [ ] Поставь `Status=Todo`.
- [ ] Дождись claim в `In Progress`.
- [ ] Проверь:
  - [ ] статус меняется в нужном Project;
  - [ ] действия идут в нужный repo;
  - [ ] state пишется в `.tmp/codex/acme`;
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
scripts/codex/run.sh watchdog_uninstall com.planka.codex-watchdog.acme
```

- [ ] Останови daemon:

```bash
scripts/codex/run.sh daemon_uninstall com.planka.codex-daemon.acme
```

- [ ] Сохрани `.tmp/codex/acme`.
- [ ] Исправь `.tmp/codex/profiles/acme.env`.
- [ ] Повтори preflight/install.

## Куда смотреть дальше
- `docs/flow-onboarding-quickstart.md`
- `docs/flow-portability-runbook.md`
- `docs/gh-app-daemon-integration-plan.md`
- `docs/flow-toolkit-packaging.md`
