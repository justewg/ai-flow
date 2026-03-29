# AI Flow PR Body — PL-116

## What
- add a dedicated `micro` execution profile for bounded low-scope tasks
- move micro-task orchestration out of the LLM path into deterministic scripts
- add per-call token telemetry, budget envelopes and hard profile-breach handling
- validate the new path with local synthetic happy-path and repair-path canaries

## Included phases
- `PL-113` micro-profile M1+M2 execution path
- `PL-114` local micro canary: happy path
- `PL-115` local micro canary: repair path
- `PL-116` hard micro-profile guard after local canaries

## Main code areas
- `scripts`
  - `executor_start.sh`
  - `executor_build_prompt.sh`
  - `executor_run.sh`
  - `run.sh`
  - `task_worktree_lib.sh`
  - new `micro_profile_lib.sh`
  - new `micro_task_classifier.sh`
  - new `context_builder.sh`
  - new `canonical_diff.sh`
  - new `metadata_builder.sh`
  - new `llm_call_telemetry.sh`
  - new `micro_profile_guard.sh`
  - new `micro_command_guard.sh`
  - new `micro_prepare_guard_bin.sh`
  - new `micro_finalize.sh`
  - new `micro_local_canary.sh`

## What changes in behaviour
- `executor_start` now classifies tasks into `standard | micro` and initializes a micro budget envelope
- `executor_build_prompt` uses `context_builder` as the only source of file-context for `micro`
- `executor_run` now has a bounded `micro` path:
  - one `implementation` call
  - deterministic checks
  - optional single `repair` call
  - deterministic diff / metadata / finalize
- per-call token telemetry is written to `llm_calls.jsonl`
- budget aggregation is written to `execution_budget.json`
- hard profile breach now returns `FAILED_PROFILE_BREACH`
- shell discovery/file-reread commands in `micro` can be blocked by guard-bin wrappers

## Validation
- `bash -n` on all touched shell entrypoints and new helper scripts
- `node --test .flow/shared/runtime-v2/test/*.test.js` -> `29/29`
- synthetic local canaries:
  - `PL-114` happy-path -> `1` call, `3456` total tokens
  - `PL-115` repair-path -> `2` calls, `6346` total tokens
  - `PL-116` guarded repair-path -> `2` calls, `6346` total tokens, no blocked commands
- direct guard smokes:
  - blocked command smoke -> `rc=126`
  - profile breach smoke -> `FAILED_PROFILE_BREACH`, `rc=42`

## Safety
- this PR changes execution-path internals, but rollout remains local-only at this stage
- real target rollout still requires a separate `planka` gitlink update and a manual VPS refresh
- synthetic canaries are local and do not push PRs or modify live project state
