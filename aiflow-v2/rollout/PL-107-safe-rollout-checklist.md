# PL-107 SAFE Rollout Checklist

Цель:
- обновить целевой checkout до changeset `PL-096..PL-106`;
- не включать automation;
- собрать reproducible SAFE validation report.

## Preconditions
- runtime/daemon/watchdog остаются выключены либо в неактивном состоянии;
- rollout выполняется из checkout на `development`;
- после merge доступны:
  - `ai-flow` integration commit из `PL-106`
  - `planka` trail commit из `PL-106`

## Command
```bash
bash aiflow-v2/rollout/pl107_safe_rollout_kit.sh
```

Локальный dry-run без `git fetch/pull`:
```bash
bash aiflow-v2/rollout/pl107_safe_rollout_kit.sh --skip-git-sync
```

## Expected outcome
- control mode становится `SAFE`
- `runtime_v2_shadow_sync` выполняется без ошибок
- `runtime_v2_inspect` показывает корректный `runtime_v2` summary
- `runtime_v2_validate_rollout` возвращает `ok=true`
- `runtime_v2_single_task_loop` возвращает `ok=true`
- `status_snapshot` содержит section `runtime_v2`

## Result artifacts
- `aiflow-v2/rollout-reports/<timestamp>/`
- основной итоговый указатель:
  - `SUMMARY.txt`
