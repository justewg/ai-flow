# AI Flow v2 Worklog

## 2026-03-28

- Инициализирован локальный `aiflow-v2/` контур в чистом worktree.
- Стартовала реализация `PL-090 / Phase A` без привязки к GitHub board из-за нестабильной сети до GitHub.
- `Phase A / PL-090` завершена: введены `AUTO | SAFE | EMERGENCY_STOP`, incident ledger, rough execution accounting и ранняя блокировка expensive runtime path вне `AUTO`.
- Для legacy runtime добавлены Phase A команды: `control_mode`, `incident_append`, `execution_summary`.
- Проверено вручную: `executor_tick`, `daemon_tick`, `watchdog_tick` корректно реагируют на `SAFE` mode.
- `Phase B / PL-091` завершена как bootstrap state layer: создан package `.flow/shared/runtime-v2` с минимальными сущностями, unified store API, `memory` adapter для локальной проверки и `mongo` adapter с явным env contract.
- Локальные проверки `runtime-v2` зелёные: schema/store tests и `getTaskBundle()` на `memory adapter`.
- `Phase C / PL-092` завершена: добавлен минимальный orchestrator `applyEvent()`, event dedup, canonical review artifact policy, terminal `WAIT_HUMAN` и active execution invariant.
- Локальные orchestrator tests зелёные: repeated finalize -> `noop`, duplicate review PR не принимается, `WAIT_HUMAN` реально блокирует expensive execution.
- `Phase D / PL-093` завершена: добавлен execution policy layer с dedup key, lease lifecycle, heartbeat и stale execution handling.
- Локальные tests зелёные: duplicate expensive run не создаётся, stale execution уходит в `failed` без restart chain.
- `Phase E / PL-094` завершена: добавлен budget/rollout policy layer с task-level caps, `emergency_stop`, `paused_budget` и explicit automation gate для controlled rollout.
- Локальные policy tests зелёные: budget breach реально стопает task, rollout modes ограничивают automation как задумано.
- `PL-095 / Integration 1` завершена: добавлен отдельный `runtime_v2` shadow contour с persistent `file` adapter и `runtime_v2_*` wrappers для sync/snapshot/clear.
- Локальный smoke подтвердил, что legacy waiting-state materialize-ится в отдельный `runtime_v2/store` как `waiting_human`, не смешиваясь с legacy state files.
