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

## Текущий статус для planka

Для `planka` этот режим уже не является экспериментом: текущий authoritative runtime живёт на VPS `ewg40` в `docker-hosted` contour, а локальный macOS runtime больше не считается рабочим контуром для очереди задач.

Зафиксированное состояние:

- рабочий contour для `planka`: `/var/sites/.ai-flow/docker/planka`;
- authoritative workspace: `/var/sites/.ai-flow/workspaces/planka`;
- post-bootstrap update path: `git pull --ff-only origin main` в `/.flow/shared`, затем `./up.sh` в `/var/sites/.ai-flow/docker/planka`;
- host-side `ops-bot`/PM2 contour снят, а `127.0.0.1:8790` закреплён за docker `ops-bot`.

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
  - поднимает `./.flow/shared/scripts/ops_bot_start.sh` и даёт loopback-local `/health`, `/ops/status`, `/ops/status.json`, webhook/ingest contour.
  - эти diagnostics surfaces в v2 считаются только internal source для publisher/helper и не должны публиковаться наружу через nginx.

Все сервисы:

- работают с `network_mode: host`;
- монтируют один и тот же authoritative workspace;
- видят host-level `AI_FLOW_ROOT` по тому же абсолютному пути;
- используют один и тот же runtime `HOME`, но не монтируют весь host home целиком: в контейнеры пробрасываются только `CODEX_HOME`, `~/.ssh`, `~/.config/gh` и каталог с `GH_APP_PRIVATE_KEY_PATH`.
- для git-доступа runtime-контур предпочитает server-side SSH dir `/etc/ai-flow/secrets/projects/<profile>/repo-ssh`, если он существует; иначе использует fallback `~/.ssh`.
- рекомендуемый production-вариант для daemon/watchdog/runtime:
  - отдельный GitHub deploy/service key;
  - файлы `id_ed25519`, `id_ed25519.pub`, `known_hosts` в `/etc/ai-flow/secrets/projects/<profile>/repo-ssh`;
  - права: каталог `0750`, приватный ключ `0640`, владелец `root:<runtime-group>`.
  - при использовании этого каталога runtime пинит `~/.ssh/id_ed25519` через `GIT_SSH_COMMAND` с `IdentitiesOnly=yes` и отдельным `UserKnownHostsFile`, чтобы не зависеть от agent/default key discovery внутри контейнера.
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

Как platform-mode `docker-hosted` всё ещё описывает первый рабочий срез и не обещает полного вытеснения host-native режима для всех профилей.

Пока это:

- воспроизводимый compose/runtime layout;
- контейнерный контур `runtime + gh-app-auth + daemon + watchdog + ops-bot`;
- точка входа для дальнейшей доработки Linux-hosted automation.

Отдельно потом можно добирать:

- container-native healthchecks для всех сервисов и агрегированный smoke;
- docker-based runbook для cutover и rollback;
- `tmux`/operator shell вокруг compose-контейнеров.

## Текущий milestone

Для `planka` cutover уже считается завершённым. На текущем срезе подтверждено:

- raw launcher `bash <(curl -fsSL ...)` реально поднимает compose-root на VPS;
- authoritative workspace и host-local `flow.env` материализуются под `/.ai-flow`;
- `gh-app-auth` внутри compose получает и refresh-ит GitHub App token;
- `daemon/watchdog` работают в контейнерах с тем же toolkit;
- `ops-bot` тоже входит в compose и использует тот же status/state контур;
- `status_snapshot` на VPS может выйти в `HEALTHY` с `daemon=IDLE_NO_TASKS` и `watchdog=HEALTHY`.
- для `planka` authoritative runtime теперь: VPS `ewg40` + `docker-hosted` contour;
- локальные `launchd`-юниты `daemon/watchdog` для `planka` сняты и не должны возвращаться как active runtime;
- старый host-side `ops-bot`/PM2 contour снят, канонический `127.0.0.1:8790` теперь занят docker `ops-bot`.

Если после этого `status_snapshot` показывает `WAIT_GITHUB_RATE_LIMIT`, это уже не проблема docker-инфраструктуры: runtime жив и упёрся в обычный GitHub GraphQL rate limit.

## Штатный update path

После первого bootstrap повторный `curl|bash` не нужен для обычного обновления runtime. Для `planka` post-bootstrap update path теперь такой и считается штатным способом обновить authoritative VPS runtime:

Важно по семантике:

- `planka` в путях вида `/var/sites/.ai-flow/workspaces/planka` здесь означает конкретный consumer-project profile.
- host-level surfaces (`ops-bot`, `gh-app-auth`, `/telegram/webhook`) не должны называться доменом проекта по умолчанию.
- для публичного ingress host-level контур лучше вешать на отдельный хост, например `aiflow.ewg40.ru`, а не смешивать с project-domain.
- status/debug diagnostics surfaces в v2 должны оставаться loopback-only и не проксироваться наружу через nginx.
- для read-only внешней AI-диагностики поверх этого контура нужно использовать отдельный `aiflow` SSH user + immutable gateway/helper + sanitized snapshots; подробности в [ai-flow-remote-agent-access.md](/private/var/sites/PLANKA/docs/ai-flow-remote-agent-access.md).

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

Смысл этого порядка такой:

- сначала подтягивается актуальный shared toolkit в authoritative workspace `planka`;
- затем compose-контур на VPS перечитывает обновлённые scripts/env wiring через `./up.sh`;
- после этого именно docker-контур остаётся единственным рабочим runtime для `planka`.

Если `git status --short` внутри authoritative workspace показывает только `M .flow/shared`, для `linux-docker-hosted` это допустимый runtime-update и не должно блокировать daemon/watchdog.

## Зафиксированный ops-bot contour для planka

Переходный host-side contour для `planka` больше не актуален:

- старый host-side `ops-bot`/PM2 runtime снят;
- `OPS_BOT_PORT` для рабочего контура должен оставаться каноническим `8790`;
- listener `127.0.0.1:8790` теперь зарезервирован под docker `ops-bot`;
- любые старые runbook-и со split `8791 -> 8790` нужно трактовать как исторический этап cutover, а не как текущую штатную схему.

Минимальная smoke-проверка после update/restart:

```bash
curl -fsS http://127.0.0.1:8790/health
```

Если health отвечает из compose-контура и `docker compose ... ps` показывает `ops-bot` в `Up`, это и есть текущий рабочий state для `planka`.

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
