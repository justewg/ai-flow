# Linux-Hosted Flow Automation Roadmap

## Цель
Перенести канонический runtime автоматики из локального MacBook на выделенный Linux VPS (reg.ru), сохранив:

- обратную совместимость toolkit для macOS;
- возможность локальной интерактивной разработки в отдельном checkout;
- единый shared toolkit в `ai-flow`;
- один и тот же daemon/executor flow (`Todo -> In Progress -> Review -> Done`).

## Почему это имеет смысл

Ожидаемые плюсы:

- server-side daemon/watchdog не зависят от sleep/wake и локальной сессии macOS;
- локальная интерактивная работа больше не конфликтует с background automation;
- runtime легче держать постоянно включенным;
- auth/ops/status/webhook contour уже естественно ложится на Linux-host;
- VPN до OpenAI уже поднят как системный сервис и может быть использован тем же host-runtime.

Главный архитектурный принцип:

- authoritative runtime для одного profile должен быть только один;
- локальный MacBook и Linux-host не должны одновременно быть active daemon-owner для одного и того же profile.

## Нецели

В этот roadmap не входят:

- отказ от macOS-режима;
- переписывание core flow-логики под новую state machine;
- отказ от текущего `ai-flow` submodule;
- миграция всех consumer-project разом;
- замена `gh_app_auth` или `ops_bot` на другие сервисы.

## Текущие ограничения

Сейчас toolkit уже хорошо переносим по коду, но service-layer ещё в основном macOS-centric:

- `daemon_install` и `watchdog_install` рассчитаны на `launchd`;
- onboarding docs описывают `launchctl` как канонический install path;
- Linux рассматривается как manual/runtime fallback, а не как полноценный first-class host;
- не зафиксирован контракт single-runtime ownership между local и remote host;
- rollback path с Linux обратно на macOS не оформлен как штатный сценарий.

## Целевое состояние

Для любого consumer-project возможны два штатных режима:

1. `macos-local`
   - daemon/watchdog как `launchd` agents;
   - локальный auth/ops contour;
   - toolkit не меняет поведение относительно текущего.

2. `linux-hosted`
   - daemon/watchdog как `systemd` services;
   - auth-service и ops-bot живут на VPS;
   - OpenAI/VPN-доступ обеспечивается host-level service layer;
   - локальный MacBook используется только для interactive development или как аварийный fallback.

## Migration strategy

Рекомендуемая последовательность:

1. Сделать Linux service-layer first-class внутри `ai-flow`, не ломая `launchd`.
2. Ввести host runtime mode (`macos-local` / `linux-hosted`) в `profile_init` и onboarding.
3. Поднять на VPS отдельный checkout `PLANKA` и прогнать там manual runtime smoke.
4. Формализовать single-runtime ownership, чтобы local daemon не конкурировал с VPS daemon.
5. Перевести `planka` на VPS как authoritative runtime.
6. Оставить macOS как supported fallback / interactive mode.

## Breakdown по задачам

### PL-048. Linux service-layer для daemon/watchdog

Цель:
- добавить `systemd`-совместимый install/runtime слой для `daemon_loop` и `watchdog_loop`.

Что должно появиться:
- `daemon_install` / `watchdog_install` умеют работать не только с `launchd`, но и с Linux host mode;
- канонические unit-files materialize-ятся так же предсказуемо, как сейчас plist на macOS;
- появляются `daemon_status` / `watchdog_status` для `systemd`;
- uninstall path симметричен install path.

Out of scope:
- перенос auth/ops сервисов;
- перенос ownership logic;
- smoke production runtime.

Acceptance:
- на Ubuntu daemon/watchdog устанавливаются, стартуют, переживают reboot;
- на macOS поведение не меняется.

### PL-049. Host mode abstraction в `profile_init` / onboarding

Цель:
- сделать Linux-hosted runtime канонической опцией конфигуратора и onboarding.

Что должно появиться:
- `FLOW_HOST_RUNTIME_MODE=macos-local|linux-hosted` или эквивалентная каноническая переменная;
- `profile_init init/install/orchestrate` выбирает нужный service backend;
- onboarding docs, quickstart и preflight различают `launchd` и `systemd`;
- `onboarding_audit` умеет проверять Linux-host prerequisites отдельно от macOS.

Acceptance:
- новый repo можно bootstrap-ить под Linux без ручной правки shell-логики;
- старый macOS path остаётся рабочим.

### PL-050. Linux-host bootstrap для executor/OpenAI/VPN contour

Цель:
- описать и автоматизировать host prerequisites для выполнения `codex exec` на VPS.

Что должно появиться:
- канонический Linux-host runtime работает под обычным пользователем automation-host, а не под `root`;
- выделенный `CODEX_HOME` на сервере (например, `~/.codex-server-api` или другой user-owned host-local path), не завязанный на репозиторий и не пишущий секреты в git;
- основной auth mode для VPS — `codex login --with-api-key`, а не перенос ChatGPT `auth.json`;
- OpenAI API key хранится только вне репозитория:
  - в host-local env file (`~/.config/<profile>/openai.env`) или `systemd EnvironmentFile`;
  - при необходимости может быть взят из уже существующего server-side secret storage другого проекта;
- отдельный `$CODEX_HOME/config.toml` для runtime-параметров `codex` (approval/sandbox/profile/provider), без хранения в нём account secrets;
- VPN prerequisite для Linux-hosted runtime оформлен как обязательный bootstrap step до smoke `codex exec`;
- явный preflight для `codex` CLI, VPN service, OpenAI reachability;
- health-check на доступ до OpenAI после старта VPN;
- runbook и/или helper для host bootstrap;
- диагностические состояния вида `WAIT_OPENAI_UNREACHABLE`, `WAIT_VPN_DOWN`.

Опорный runbook:
- `docs/linux-hosted-codex-api-bootstrap.md`
  - содержит реестр того, что должно быть на сервере;
  - содержит блок `Dependencies install`;
  - фиксирует канонический API-key auth path для Linux-hosted `codex`.

Что уже подтверждено руками на reg.ru VPS:
- `codex` на сервере успешно установлен и запускается под обычным пользователем;
- схема с перенесённым ChatGPT `auth.json` не является надёжной для VPS/VPN-path и дала `403` на `chatgpt.com/backend-api/codex/responses`;
- схема с `OpenAI API key` подтверждённо работает:
  - `CODEX_HOME="$HOME/.codex-server-api" codex login status` показывает `Logged in using an API key`;
  - `CODEX_HOME="$HOME/.codex-server-api" codex exec "Ответь ровно строкой OK"` успешно выполняется;
- до запуска `codex` на VPS требуется поднять VPN через safe-wrapper (`~/vpn.sh start`) и подтвердить внешний IP (`~/vpn.sh ip`); wrapper должен сохранять `/32` route до текущего SSH client IP, чтобы full-tunnel OpenVPN не рвал активную SSH-сессию.

Канонический server-side smoke для этой задачи:
1. Поднять VPN:
   - `~/vpn.sh start`
   - `~/vpn.sh ip`
2. Подготовить user-owned `CODEX_HOME`:
   - `mkdir -p ~/.codex-server-api && chmod 700 ~/.codex-server-api`
3. Залогинить `codex` через API key:
   - `printf '%s' "$OPENAI_API_KEY" | CODEX_HOME="$HOME/.codex-server-api" codex login --with-api-key`
4. Проверить статус:
   - `CODEX_HOME="$HOME/.codex-server-api" codex login status`
5. Прогнать smoke:
   - `CODEX_HOME="$HOME/.codex-server-api" codex exec "Ответь ровно строкой OK"`

Источник секрета:
- не repo-level `.env`;
- не `flow.env`;
- а host-local secret file/secret store вне git;
- в уже проведённом smoke использовался существующий API key, ранее сохранённый в env на сервере для другого проекта.

Acceptance:
- на VPS можно подтверждённо запускать executor через `OpenAI API key` без ручной магии между ребутами;
- после первичной настройки headless runtime не требует ручного браузерного логина на сервере;
- preflight явно показывает, чего не хватает.

Текущий срез:
- базовый Linux-host preflight уже материализован в `.flow/shared/scripts/linux_host_codex_preflight.sh`;
- `profile_init preflight` начал включать этот набор проверок для `linux-hosted` / `linux-docker-hosted`;
- следующий шаг по задаче: добить branch/runtime drift и повторить `PL-059` до полного happy-path.

### PL-051. Single-runtime ownership и защита от dual-daemon

Цель:
- не дать двум хостам одновременно быть authoritative automation runtime для одного profile.

Что должно появиться:
- machine/host identity в runtime state;
- guard, который запрещает local и remote daemon одновременно брать одну и ту же очередь;
- явный режим `interactive-only` для локального checkout;
- recovery/override path, если host сменился.

Acceptance:
- локальный интерактивный checkout не мешает server-side executor-run;
- случайный второй daemon не забирает ту же задачу.

### PL-052. Linux-host auth/ops contour как штатный runtime

Цель:
- перевести `gh_app_auth` и `ops_bot` в first-class Linux-host mode.

Что должно появиться:
- понятный способ запускать auth-service и ops-bot на VPS;
- restart policy и health checks после reboot;
- интеграция с текущим `/ops/status`, Telegram webhook и remote snapshot ingest;
- единый runbook для локального и удалённого размещения.

Acceptance:
- после reboot VPS auth/ops stack поднимается без ручного вмешательства;
- daemon/watchdog получают нужные токены и status surface остаётся живым.

### PL-053. Smoke migration `planka -> reg.ru`

Цель:
- перевести `planka` на VPS как authoritative runtime и подтвердить end-to-end flow.

Что должно быть проверено:
- `Todo -> In Progress -> Review -> Done`;
- branch sync, executor resume, review feedback, task finalize;
- watchdog recovery;
- coexistence с локальной интерактивной разработкой;
- корректная работа ops/status и Telegram signals.

Acceptance:
- минимум один полноценный smoke без ручного доталкивания;
- локальный MacBook не ломает server runtime при отдельной interactive работе.

### PL-054. Runbook, rollback и эксплуатационный режим

Цель:
- оформить Linux-hosted automation как поддерживаемый эксплуатационный сценарий.

Что должно появиться:
- канонический runbook запуска/обновления/rollback;
- инструкция переключения `authoritative runtime` между Mac и VPS;
- checklist диагностики;
- policy, какой host считается рабочим для конкретного profile.

Acceptance:
- новый инженер может поднять или вернуть runtime по документированному сценарию;
- rollback с VPS обратно на Mac не требует reverse-engineering.

## Рекомендуемый порядок

1. `PL-048`
2. `PL-049`
3. `PL-050`
4. `PL-051`
5. `PL-052`
6. `PL-053`
7. `PL-054`

## Критерий завершения всей инициативы

Инициатива считается завершённой, когда:

- `planka` штатно работает на Linux VPS как authoritative runtime;
- local MacBook остаётся supported interactive/fallback contour;
- toolkit не теряет совместимость с `launchd`;
- перенос на Linux документирован и повторяем;
- smoke подтверждает, что server-side automation не мешает локальной разработке и наоборот.
