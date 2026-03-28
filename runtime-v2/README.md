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
