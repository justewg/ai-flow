# Docker-Hosted AI Flow Bootstrap

## Зачем нужен этот режим

`linux-hosted` через host-native `systemd` остаётся каноническим режимом для VPS, но для части серверных сценариев он даёт слишком много ручной конфигурации:

- системные пакеты и их версии живут на хосте;
- `gh`, `codex`, `node`, `git`, `ripgrep` и прочие зависимости надо ставить отдельно;
- runtime легче загрязняется host-specific drift;
- разбор полётов часто сводится к тому, что именно сломано на этой конкретной машине.

`docker-hosted` вводится как отдельный deployment mode:

- installer задаёт вопросы;
- готовит authoritative workspace и host-local `flow.env`;
- генерирует `docker-compose.yml`, `Dockerfile`, helper scripts и env files;
- при желании сразу запускает контейнеры.

## Что это даёт

- воспроизводимый runtime image;
- тонкий host bootstrap: достаточно `docker`, `docker compose`, SSH до GitHub и доступа к OpenAI/VPN;
- одинаковый compose layout для `runtime`, `daemon`, `watchdog`;
- секреты и state остаются вне git, но не размазываются по всей машине.

## Что генерируется

По умолчанию generator создаёт:

- authoritative workspace:
  - `/var/sites/.ai-flow/workspaces/<profile>`
- host-level platform env:
  - `/var/sites/.ai-flow/config/ai-flow.platform.env`
- host-local flow env:
  - `/var/sites/.ai-flow/config/<profile>.flow.env`
- docker root:
  - `/var/sites/.ai-flow/docker/<profile>`

Внутри docker root:

- `Dockerfile`
- `docker-compose.yml`
- `.env`
- `container.env`
- `up.sh`
- `down.sh`
- `logs.sh`
- `exec-runtime.sh`

## Разделение platform env и project env

Семантика должна быть такой:

- `ai-flow.platform.env`
  - host-level и platform-level настройки;
  - public ingress/base URL;
  - host-level `ops-bot` / `gh-app-auth` defaults;
  - debug bearer token и другие не-project-specific секреты.
- `<profile>.flow.env`
  - только project/runtime binding конкретного consumer-project;
  - repo/project profile;
  - project state/log paths;
  - project-specific automation tokens и прочий runtime binding.

Для `planka` это означает:

- platform env:
  - `/var/sites/.ai-flow/config/ai-flow.platform.env`
- project env:
  - `/var/sites/.ai-flow/config/planka.flow.env`

Отдельный разбор `required / optional / legacy` по env см. в:

- [ai-flow-env-checklist.md](/private/var/sites/PLANKA/docs/ai-flow-env-checklist.md)

## Контейнерная схема

Текущий рабочий срез содержит 5 сервисов:

- `runtime`
  - long-lived shell container для `codex`, `gh`, ручных smoke-команд и интерактивной отладки;
- `gh-app-auth`
  - поднимает `gh_app_auth_service.js` внутри compose и даёт `daemon/watchdog` штатный auth contour на `127.0.0.1:8787`;
- `daemon`
  - запускает `./.flow/shared/scripts/daemon_loop.sh <interval>`;
- `watchdog`
  - запускает `./.flow/shared/scripts/watchdog_loop.sh <interval>`.
- `ops-bot`
  - поднимает `./.flow/shared/scripts/ops_bot_start.sh` и даёт локальные `/health`, `/ops/status`, `/ops/status.json`, webhook/ingest contour.
  - при включённом `OPS_BOT_DEBUG_ENABLED` также даёт защищённые `/ops/debug/*` endpoints для remote diagnosis without SSH.

Все сервисы:

- работают с `network_mode: host`;
- монтируют один и тот же authoritative workspace;
- видят host-level `AI_FLOW_ROOT` по тому же абсолютному пути;
- используют один и тот же runtime `HOME` и `CODEX_HOME`.
- `daemon` и `watchdog` стартуют только после healthy `gh-app-auth`.
- `ops-bot` живёт в том же compose-контуре и использует тот же workspace/state/log layout.
- host-level переменные сервисов приходят из `ai-flow.platform.env`, project-specific — из `<profile>.flow.env`.

## Ключевое предположение

По умолчанию считается, что host уже имеет доступ к OpenAI:

- либо напрямую;
- либо через поднятый на хосте VPN.

Поэтому контейнеры используют:

```yaml
network_mode: host
```

Это сознательный дизайн первого среза: не прятать сетевую сложность внутрь контейнера, а использовать уже подтверждённый host path до OpenAI.

## Что должен уметь хост

Минимум:

- `docker`
- `docker compose`
- `git`
- SSH-доступ к GitHub
- доступ к OpenAI/VPN

Опционально, но желательно:

- `gh` для ручной диагностики на хосте;
- `tmux` для операторской оболочки, если потребуется работать без Docker exec.

## Что пока не обещается

Первый рабочий срез не обещает полного вытеснения host-native режима.

Пока это:

- воспроизводимый compose/runtime layout;
- контейнерный контур `runtime + gh-app-auth + daemon + watchdog + ops-bot`;
- точка входа для дальнейшей доработки Linux-hosted automation.

Отдельно потом можно добирать:

- container-native healthchecks для всех сервисов и агрегированный smoke;
- docker-based runbook для cutover и rollback;
- `tmux`/operator shell вокруг compose-контейнеров.

## Текущий milestone

На текущем срезе уже подтверждено:

- raw launcher `bash <(curl -fsSL ...)` реально поднимает compose-root на VPS;
- authoritative workspace и host-local `flow.env` материализуются под `/.ai-flow`;
- `gh-app-auth` внутри compose получает и refresh-ит GitHub App token;
- `daemon/watchdog` работают в контейнерах с тем же toolkit;
- `ops-bot` тоже входит в compose и использует тот же status/state контур.
- `status_snapshot` на VPS может выйти в `HEALTHY` с `daemon=IDLE_NO_TASKS` и `watchdog=HEALTHY`.

Если после этого `status_snapshot` показывает `WAIT_GITHUB_RATE_LIMIT`, это уже не проблема docker-инфраструктуры: runtime жив и упёрся в обычный GitHub GraphQL rate limit.

## Штатный update path

После первого bootstrap повторный `curl|bash` не нужен для обычного обновления runtime.

Важно по семантике:

- `planka` в путях вида `/var/sites/.ai-flow/workspaces/planka` здесь означает конкретный consumer-project profile.
- host-level surfaces (`ops-bot`, `gh-app-auth`, `/ops/status`, `/ops/debug/*`, `/telegram/webhook`) не должны называться доменом проекта по умолчанию.
- для публичного ingress host-level контур лучше вешать на отдельный хост, например `aiflow.ewg40.ru`, а не смешивать с project-domain.

Штатный путь такой:

```bash
cd /var/sites/.ai-flow/workspaces/planka/.flow/shared
git pull --ff-only origin main
```

```bash
cd /var/sites/.ai-flow/docker/planka
./up.sh
docker compose --env-file .env -f docker-compose.yml ps
```

Если `git status --short` внутри authoritative workspace показывает только `M .flow/shared`, для `linux-docker-hosted` это допустимый runtime-update и не должно блокировать daemon/watchdog.

## Временный ops-bot port split

Если на хосте уже живёт старый host-side `ops-bot` на `127.0.0.1:8790`, безопасный первый cutover такой:

- docker `ops-bot` временно переводится на `8791` через `OPS_BOT_PORT=8791` в host-local `flow.env`;
- старый host-side contour продолжает жить на `8790`;
- новый compose contour проверяется отдельно через `curl http://127.0.0.1:8791/health`.

После подтверждения работы docker `ops-bot` перенос на канонический `8790` делается отдельным шагом.

## Cutover 8791 -> 8790

Безопасный порядок:

1. Найти старый listener:
   - `ss -ltnp | grep 8790`
   - `ps -ef | grep ops_bot | grep -v grep`
   - при необходимости `pm2 ls`
2. Остановить старый host-side `ops-bot` или его supervisor.
3. Вернуть в `/var/sites/.ai-flow/config/planka.flow.env`:
   - `OPS_BOT_PORT=8790`
4. Переподнять compose:

```bash
cd /var/sites/.ai-flow/docker/planka
./up.sh
docker compose --env-file .env -f docker-compose.yml ps
```

5. Проверить:

```bash
curl -fsS http://127.0.0.1:8790/health
```

Если health отвечает из docker contour, старый ops runtime можно считать полностью заменённым.

## Запуск

Raw launcher:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-docker-init.sh)
```

Shared command внутри checkout:

```bash
./.flow/shared/scripts/run.sh docker_bootstrap
```

## Smoke после генерации

Если generator уже отрисовал compose root:

```bash
cd /var/sites/.ai-flow/docker/planka
./up.sh
docker compose --env-file .env -f docker-compose.yml ps
./logs.sh gh-app-auth
./logs.sh ops-bot
./logs.sh daemon
./exec-runtime.sh
```

Внутри `runtime` контейнера дальше можно проверять:

```bash
cd /var/sites/.ai-flow/workspaces/planka
codex --version
gh --version
./.flow/shared/scripts/run.sh onboarding_audit --profile planka
```
