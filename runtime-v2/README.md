# AI Flow Runtime v2

Минимальный bootstrap state-store для `AI Flow v2`.

## Что входит
- минимальные сущности:
  - `Task`
  - `TaskState`
  - `Execution`
  - `Event`
- единый `AiFlowV2StateStore`
- минимальный orchestrator `applyEvent()`
- `memory` adapter для локальной разработки и unit/smoke checks
- `mongo` adapter с явным env/dependency contract

## Phase B scope
- это bootstrap persistent state layer
- runtime orchestration сюда ещё не подключена
- canonical review / WAIT_HUMAN / dedup policy будут на следующих фазах

## Phase C additions
- `applyEvent()` реализует минимальный transition engine поверх store
- уже внедрены:
  - active execution invariant
  - canonical review artifact policy
  - terminal `WAIT_HUMAN`
  - duplicate-event no-op по `dedupKey`

## Phase D additions
- execution control layer:
  - `buildExecutionDedupKey()`
  - `acquireExecutionLease()`
  - `heartbeatExecutionLease()`
  - `releaseExecutionLease()`
  - `evaluateExecutionStaleness()`
  - `markExecutionStale()`
- duplicate expensive execution блокируется по execution dedup key
- stale execution переводится в terminal failed state без auto-restart

## Phase E additions
- budget / rollout policy layer:
  - `evaluateTaskBudget()`
  - `enforceTaskBudget()`
  - `evaluateRolloutGate()`
  - `evaluateAutomationGate()`
- базовые states:
  - `paused_budget`
  - `emergency_stop`
- rollout scaffold:
  - `dry_run`
  - `shadow`
  - `single_task`
  - `limited`
  - `auto`

## Integration 1 additions
- отдельный `v2`-контур для shadow bridge:
  - `createFileAdapter()` для persistent local v2 state
  - `runtime_v2_shadow_sync.sh`
  - `runtime_v2_snapshot.sh`
  - `runtime_v2_clear.sh`
- persistent shadow state хранится отдельно от legacy runtime в `<state-dir>/runtime_v2/store`
- bridge читает legacy state files и materialize-ит v2 task/taskState/execution/events без переключения текущей automation

## Integration 2 additions
- policy-first gate bridge:
  - `evaluateLegacyPolicyGate()`
  - `runtime_v2_gate.js`
  - `runtime_v2_gate.sh`
- legacy shell runtime перед expensive/recovery paths сначала sync-ит shadow state и читает `rollout / budget / stale` verdict из `runtime-v2`
- gate остаётся отдельным `v2`-контуром и не заменяет ещё весь legacy control plane

## Integration 3 additions
- event bridge into orchestrator:
  - `applyLegacyEventBridge()`
  - `runtime_v2_apply_event.js`
  - `runtime_v2_apply_event.sh`
- selected legacy lifecycle transitions (`wait / response / review / execution`) теперь могут materialize-иться в `runtime-v2 applyEvent()`
- bridge остаётся best-effort sidecar: legacy scripts ещё не заменены полностью, но `runtime-v2` уже получает canonical transitions не только через shadow projection

## Integration 4 additions
- primary-source bridge for selected contexts:
  - `derivePrimaryContexts()`
  - `runtime_v2_primary_context.js`
  - `runtime_v2_primary_context.sh`
  - `runtime_v2_reconcile_primary_context.sh`
- `runtime-v2` становится primary source для selected `executing / reviewing` contexts
- legacy `daemon/watchdog` перед основной логикой выравнивают `daemon_active_*` и `daemon_review_*` из `runtime-v2` store

## Integration 5 additions
- `WAIT_HUMAN` переведён в primary-source mode:
  - waiting metadata живёт в `taskState.meta.waiting`
  - `runtime_v2_reconcile_primary_context.sh` materialize-ит legacy `daemon_waiting_*` из `runtime-v2`
- ordinary wait теперь идёт через `human.wait_requested` event, а не только через legacy state files

## Integration 6 additions
- review/wait business transitions переведены на `emit event -> reconcile`
- review-feedback waiting materialize-ится из `reviewing` state через `meta.reviewFeedback`

## Integration 7 additions
- legacy watchdog перестроена в supervisor-style слой:
  - freeze / stop / alert
  - без auto-heal restart loops как primary behaviour

## Integration 8 additions
- budget/quota/circuit-breaker authority идёт через `runtime-v2`:
  - `budget.breached`
  - `deriveGlobalControlMode()`
  - `runtime_v2_sync_control_mode.sh`

## Integration 9 additions
- operator inspection surfaces:
  - `buildInspectionSummary()`
  - `runtime_v2_inspect.js`
  - `runtime_v2_inspect.sh`
- `status_snapshot.sh` теперь включает section `runtime_v2` c:
  - control mode
  - task counts by phase/budget/lock
  - primary contexts
  - recent incidents
  - execution summary

## Integration 10 additions
- rollout validation harness:
  - `runRolloutValidation()`
  - `runtime_v2_validate_rollout.js`
  - `runtime_v2_validate_rollout.sh`
- harness последовательно проверяет:
  - `dry_run` блокирует expensive daemon/executor paths
  - `shadow` блокирует side-effect paths
  - `shadow` сохраняет read-only inspection path
  - `WAIT_HUMAN` context продолжает materialize-иться в inspection summary

## Integration 11 additions
- controlled single-task loop harness:
  - `runSingleTaskLoop()`
  - `runtime_v2_single_task_loop.js`
  - `runtime_v2_single_task_loop.sh`
- harness подтверждает:
  - allowlisted task проходит `single_task` rollout gate
  - non-allowlisted task получает `rollout_single_task_denied`
  - canonical event chain `execution.started -> execution.finished -> human.wait_requested -> human.response_received -> review.finalized`
  - итоговый primary context = `reviewing`

## Env contract
- `AIFLOW_V2_MONGODB_URI`
- `AIFLOW_V2_MONGODB_DB`
- `AIFLOW_V2_MONGODB_COLLECTION_PREFIX` optional, default: `aiflow_v2`

## Коллекции
- `<prefix>_tasks`
- `<prefix>_task_states`
- `<prefix>_executions`
- `<prefix>_events`

## Пример
```js
const {
  createMemoryAdapter,
  createAiFlowV2StateStore,
} = require("./src");

const store = createAiFlowV2StateStore({
  adapter: createMemoryAdapter(),
});

await store.putTask({
  id: "PL-091",
  title: "State store bootstrap",
  repo: "justewg/planka",
});

await store.putTaskState({
  taskId: "PL-091",
  phase: "planned",
  reason: "bootstrap",
  ownerMode: "human",
});

console.log(await store.getTaskBundle("PL-091"));
```
