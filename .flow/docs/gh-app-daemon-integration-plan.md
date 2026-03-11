# GitHub App + Daemon Integration Plan

## Цель
Перевести daemon/watchdog с пользовательского PAT на GitHub App, чтобы:
- GitHub-активность автоматики шла от `app-name[bot]`;
- уменьшить риски доступа (короткоживущие installation tokens);
- сохранить текущий flow `Backlog -> Todo -> In Progress -> Review -> Done`.

## Архитектура
1. Локальный auth-сервис (Node.js) получает installation token GitHub App.
2. Daemon/Watchdog берут токен у локального сервиса перед GitHub-операциями.
3. Токен живет коротко, сервис обновляет его заранее.
4. Fallback: если App-сервис недоступен, можно временно включить `DAEMON_GH_TOKEN`.

## Ограничение user-owned Project v2
Если Project принадлежит пользователю (owner type `User`, endpoint вида `/users/{username}/projectsV2`), GitHub App installation token не дает полноценный доступ к Project API.

Практический режим без организации (hybrid):
1. App token — для `Issue/PR` (бот-авторство сохраняется).
2. `DAEMON_GH_PROJECT_TOKEN` — для операций Project v2 (чтение карточек/смена `Status/Flow`).

## Шаги в GitHub UI
1. Создать GitHub App (`Settings -> Developer settings -> GitHub Apps`).
2. Выдать минимальные permissions:
- Repository `Issues: Read & write`
- Repository `Pull requests: Read & write`
- Repository `Metadata: Read-only`
- Repository `Contents: Read-only` (или выше, если потребуется)
- Project/Projects permissions для Project v2 с правом редактирования (если доступны в UI)
3. Установить App на owner/repo `<owner>/<repo>`.
4. Проверить доступ App к Project v2 (карточки/поля/статусы).
5. Скачать private key `.pem`.

## Локальная конфигурация
Добавить в `.env`:
- `GH_APP_ID=...`
- `GH_APP_INSTALLATION_ID=...`
- `GH_APP_PRIVATE_KEY_PATH=...`
- `GH_APP_OWNER=<owner>`
- `GH_APP_REPO=<repo>`
- `GH_APP_BIND=127.0.0.1`
- `GH_APP_PORT=8787`
- `GH_APP_INTERNAL_SECRET=...`
- `GH_APP_TOKEN_SKEW_SEC=300`

Опционально аварийный fallback:
- `DAEMON_GH_TOKEN=...`
  - источник: PAT (лучше от отдельного bot-аккаунта)
  - путь в UI: `Settings -> Developer settings -> Personal access tokens`
  - минимальные scopes для текущего flow: `repo`, `read:project`, `project`
  - рекомендуемые дополнительные scopes для совместимости: `read:org`, `read:discussions`

Для user-owned Project v2 (hybrid mode):
- `DAEMON_GH_PROJECT_TOKEN=...`
  - отдельный PAT только для Project v2 операций.
  - где получить: `GitHub -> Settings -> Developer settings -> Personal access tokens`.
  - рекомендуемый тип: `Tokens (classic)` для совместимости с user-owned Project API.
  - минимальные scopes: `repo`, `read:project`, `project`.
  - рекомендуемые дополнительные scopes: `read:org`, `read:discussions`.

## Мини-сервис (Node.js)
### Обязательные endpoint-ы
1. `GET /health`
2. `GET /token` (защищен `X-Internal-Secret`)

### Требования
1. Кэшировать installation token в памяти.
2. Обновлять токен заранее (`expires_at - skew`).
3. Не логировать токены/ключи.
4. Слушать только `127.0.0.1`.
5. Возвращать диагностические коды ошибок, понятные daemon/watchdog.

## Интеграция в daemon/watchdog
1. Добавить шаг получения `GH_TOKEN` из auth-сервиса перед GitHub-вызовами.
2. При ошибке auth-сервиса:
- не выполнять GitHub-мутирующие действия;
- писать `WAIT_AUTH_SERVICE` в state/detail;
- отправлять сигнал в Telegram, если доступен.
3. Сохранить fallback на `DAEMON_GH_TOKEN` (feature flag).

## PM2
1. Поднять auth-сервис под `pm2` с авто-рестартом.
2. Вынести логи в отдельные файлы.
3. Добавить health-check команду.

## Риски
1. `Resource not accessible by integration` для Project v2.
2. Нехватка scopes/permissions при установке App.
3. Ошибки ротации токена (протухание, недоступность auth-сервиса).

## Runbook: APP-07.5 (доступ GitHub App к Project v2)
Цель: убрать блокер `Resource not accessible by integration` и подтвердить, что App может читать/менять карточки Project.

### Шаг 1. Проверить permissions GitHub App в UI
Путь: `GitHub -> Settings -> Developer settings -> GitHub Apps -> <ваш app> -> Permissions & events`.

Что должно быть включено:
1. `Repository permissions`:
- `Issues: Read and write`
- `Pull requests: Read and write`
- `Metadata: Read-only`
- `Contents: Read-only`
2. `Account permissions` (для user-owned project) или `Organization permissions` (для org-owned project):
- `Projects: Read and write`

Важно:
1. Если меняли permissions, нажать `Save changes`.
2. После сохранения обязательно обновить installation (следующий шаг), иначе новые права не применятся к installation token.

### Шаг 2. Обновить installation App
Путь: `GitHub -> Settings -> Applications -> Installed GitHub Apps -> <ваш app> -> Configure`.

Что сделать:
1. Убедиться, что installation активен для нужного owner.
2. В `Repository access` выбрать `Only selected repositories` и проверить, что нужный repo включен.
3. Подтвердить/re-authorize, если GitHub запрашивает подтверждение после изменения permissions.

### Шаг 3. Проверить доступ к Project через App token (локально)
1. Получить installation token:
`app_token="$(.flow/scripts/gh_app_auth_token.sh)"`
2. Проверить чтение Project:
`GH_TOKEN="$app_token" gh api graphql -f query='query($projectId:ID!){ node(id:$projectId){ __typename ... on ProjectV2 { id title number } } }' -f projectId='<PROJECT_ID>'`
3. Проверить мутацию Project (на тестовом item id):
`GH_TOKEN="$app_token" .flow/scripts/project_set_status.sh <project-item-id> "Todo" "Ready"`

Ожидаемый результат:
1. `node` не `null`, без `Resource not accessible by integration`.
2. `project_set_status.sh` завершается успешно (`Updated ...`).

Если у вас user-owned Project и ответ стабильно `Resource not accessible by integration`:
1. Это известное ограничение GitHub App для user-owned Project API.
2. Включите hybrid mode через `DAEMON_GH_PROJECT_TOKEN`.
3. Повторите проверку Project-операций через:
`GH_TOKEN="$DAEMON_GH_PROJECT_TOKEN" .flow/scripts/project_set_status.sh <project-item-id> "Todo" "Ready"`

### Шаг 4. Повторить smoke daemon-flow по Project
1. Перевести тестовую карточку в `Status=Todo, Flow=Ready`.
2. Дождаться claim демоном в `In Progress`.
3. Подтвердить actor в Project events = `app-name[bot]`.
4. Завершить цикл до `Review/Done`.

### Диагностика типовых ошибок
1. `Resource not accessible by integration`:
- не выданы `Projects` permissions App;
- installation не обновлен после изменения permissions;
- App установлен не на того owner или не на тот repo.
2. `Could not resolve to a ProjectV2 ...` в daemon-log:
- токен App есть, но нет доступа к конкретному Project;
- проверить owner/тип Project (user vs org) и соответствующий permission scope.
3. Для user-owned project ошибка не исчезает после переустановки App:
- включить hybrid mode с `DAEMON_GH_PROJECT_TOKEN`;
- перезапустить daemon/watchdog;
- повторить smoke.

## Критерии приемки
1. Комментарии в Issue от `app-name[bot]`.
2. PR create/edit от `app-name[bot]`.
3. Обновление статусов Project от `app-name[bot]`.
4. Daemon работает >65 минут без auth-сбоев.
5. При недоступном auth-сервисе daemon корректно уходит в ожидание и сигнализирует.

## Онбординг сервиса (включение App auth в текущем окружении)
Минимальный checklist для нового хоста/аккаунта:
1. Заполнить `.env`:
- `GH_APP_ID`
- `GH_APP_INSTALLATION_ID`
- `GH_APP_PRIVATE_KEY_PATH`
- `GH_APP_INTERNAL_SECRET`
- `GH_APP_OWNER=<owner>`
- `GH_APP_REPO=<repo>`
- `GH_APP_BIND=127.0.0.1`
- `GH_APP_PORT=8787`
2. Убедиться, что fallback выключен (штатный режим App):
- не задавать `DAEMON_GH_TOKEN_FALLBACK_ENABLED=1`
- не задавать `DAEMON_GH_TOKEN` / `CODEX_GH_TOKEN`, если аварийный fallback не нужен
3. Для user-owned Project v2 задать hybrid token:
- `DAEMON_GH_PROJECT_TOKEN=<PAT с repo,read:project,project>`
4. Запустить auth-сервис:
- `.flow/scripts/run.sh gh_app_auth_pm2_start`
- `.flow/scripts/run.sh gh_app_auth_pm2_health`
5. Перезапустить automation:
- `.flow/scripts/run.sh daemon_uninstall <daemon-label>`
- `.flow/scripts/run.sh daemon_install <daemon-label> 90`
- `.flow/scripts/run.sh watchdog_uninstall <watchdog-label>`
- `.flow/scripts/run.sh watchdog_install <watchdog-label> 90`
6. Проверить state:
- `cat .flow/state/codex/daemon_state.txt`
- `cat .flow/state/codex/daemon_state_detail.txt`
- `cat .flow/state/codex/watchdog_state.txt`
7. Проверить деградацию/восстановление auth:
- `.flow/scripts/run.sh gh_app_auth_pm2_stop` -> ожидать `WAIT_AUTH_SERVICE` + Telegram `ENTER_DEGRADED`
- `.flow/scripts/run.sh gh_app_auth_pm2_start` -> ожидать выход из `WAIT_AUTH_SERVICE` + Telegram `RECOVERED`

## Разбиение на задачи (для Project)
1. `APP-01` Создать GitHub App и выдать permissions.
2. `APP-02` Установить App на repo/project и проверить доступы.
3. `APP-03` Поднять Node.js auth-сервис (JWT + installation token).
4. `APP-04` Подключить daemon/watchdog к auth-сервису.
5. `APP-05` Добавить fallback-режим и деградационные сигналы.
6. `APP-06` Добавить запуск/мониторинг auth-сервиса через PM2.
7. `APP-07` Провести интеграционный smoke-test полного flow.
8. `APP-08` Реализовать проверку `Flow Meta -> Depends-On` в daemon.
9. `APP-09` Добавить генерацию диаграммы зависимостей (Mermaid) из `Flow Meta`.

## Детализация APP-01
Цель: подготовить GitHub App для auth-интеграции демона.

Шаги:
1. `Settings -> Developer settings -> GitHub Apps -> New GitHub App`.
2. Заполнить базовые поля:
- `GitHub App name` (уникальный, например `flow-daemon-auth`);
- `Homepage URL` (`https://github.com/<owner>/<repo>`);
- Webhook на этом этапе отключить.
3. Выдать permissions:
- `Issues: Read and write`;
- `Pull requests: Read and write`;
- `Contents: Read-only`;
- `Metadata: Read-only`;
- `Projects/Project v2: Read and write` (если доступно в UI).
4. Создать App.
5. В App: `Private keys -> Generate a private key` и сохранить `.pem` вне репозитория.
6. Зафиксировать данные для следующих шагов:
- `App ID`;
- имя App;
- путь к `.pem`.

Критерии приемки:
1. App создан и виден в списке GitHub Apps.
2. Приватный ключ сгенерирован.
3. Есть полный набор исходных данных для `APP-02/APP-03`.

## Детализация APP-02
Цель: установить App и подтвердить доступы к `repo + project`.

Шаги:
1. Открыть App из `APP-01` и выбрать `Install App`.
2. Установить на нужного owner.
3. Ограничить доступ репозиториями:
- предпочтительно `Only selected repositories -> <repo>`.
4. Проверить права на Project v2 (`PLANKA Roadmap #2`) и при необходимости добавить write-доступ.
5. Зафиксировать:
- `Installation ID`;
- owner/repo scope (`<owner>/<repo>`).
6. Подготовить значения для `.env` (без запуска интеграции):
- `GH_APP_ID=...`
- `GH_APP_INSTALLATION_ID=...`
- `GH_APP_PRIVATE_KEY_PATH=<HOME>/.secrets/gh-apps/codex-flow.private-key.pem`
- `GH_APP_OWNER=<owner>`
- `GH_APP_REPO=<repo>`

Критерии приемки:
1. App установлен на нужный `<owner>/<repo>`.
2. Доступ к Project подтвержден.
3. Собраны входные данные для старта `APP-03`.

## Граф зависимостей (план)
- `APP-01 -> APP-02 -> APP-03 -> APP-04 -> APP-05`
- `APP-03 -> APP-06`
- `APP-04 + APP-05 + APP-06 -> APP-07`
- `APP-04 -> APP-08`
- `APP-08 -> APP-09`

## Актуальная Mermaid-диаграмма APP-зависимостей
Обновление диаграммы перед docs/PR:
1. Выполнить `.flow/scripts/run.sh app_deps_mermaid`.
2. Проверить/вставить файл `docs/app-issues-dependency-diagram.md`.
3. Если нужен другой путь вывода: `.flow/scripts/run.sh app_deps_mermaid <output-file>`.
