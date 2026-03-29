# AI Flow PR Body — PL-106

## What
- continue the `runtime-v2` cutover from sidecar state into primary control-plane responsibilities
- make `WAIT_HUMAN`, review anchors, supervisor freezes and budget stops authoritative from `runtime-v2`
- add operator inspection, rollout validation and single-task local loop harnesses

## Included phases
- `PL-096` policy-first gating
- `PL-097` event bridge into `applyEvent()`
- `PL-098` primary-source active/review contexts
- `PL-099` primary-source `WAIT_HUMAN`
- `PL-100` review/wait transitions via `event -> reconcile`
- `PL-101` watchdog -> supervisor
- `PL-102` budget/quota/circuit-breaker authority
- `PL-103` operator inspection surfaces
- `PL-104` `dry_run/shadow` validation harness
- `PL-105` controlled `single_task` local loop harness

## Main code areas
- `runtime-v2/src`
  - `legacy_gate.js`
  - `legacy_event_bridge.js`
  - `primary_context.js`
  - `control_policy.js`
  - `inspection.js`
  - `validation.js`
  - `single_task_loop.js`
  - updates in `orchestrator.js`, `legacy_shadow.js`, `store.js`, adapters and exports
- `runtime-v2/bin`
  - `runtime_v2_apply_event.js`
  - `runtime_v2_gate.js`
  - `runtime_v2_primary_context.js`
  - `runtime_v2_control_mode.js`
  - `runtime_v2_inspect.js`
  - `runtime_v2_validate_rollout.js`
  - `runtime_v2_single_task_loop.js`
- `scripts`
  - `daemon_tick.sh`
  - `watchdog_tick.sh`
  - `executor_start.sh`
  - `executor_run.sh`
  - `task_ask.sh`
  - `daemon_check_replies.sh`
  - `task_finalize.sh`
  - `status_snapshot.sh`
  - `run.sh`
  - `README.md`
  - new `runtime_v2_*` wrappers

## Validation
- `node --test .flow/shared/runtime-v2/test/*.test.js` -> `28/28`
- `bash -n` on touched shell wrappers and entrypoints
- local smokes:
  - `runtime_v2_inspect`
  - `runtime_v2_validate_rollout`
  - `runtime_v2_single_task_loop`

## Safety
- no auto-rollout is enabled here
- target environment is expected to stay in `SAFE` during first update
- rollout progression after merge remains:
  - manual SAFE update
  - local validation on target
  - limited rollout only after explicit confirmation
