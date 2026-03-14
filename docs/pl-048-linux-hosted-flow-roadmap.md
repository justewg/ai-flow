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
- явный preflight для `codex` CLI, VPN service, OpenAI reachability;
- health-check на доступ до OpenAI после старта VPN;
- runbook и/или helper для host bootstrap;
- диагностические состояния вида `WAIT_OPENAI_UNREACHABLE`, `WAIT_VPN_DOWN`.

Acceptance:
- на VPS можно подтверждённо запускать executor без ручной магии между ребутами;
- preflight явно показывает, чего не хватает.

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
