# PL-108 Limited Rollout Checklist

Цель:
- после успешного SAFE validation перевести target env в `limited` rollout;
- разрешить automation только для явного allowlist task ids;
- не переходить в `auto`.

## Step 1
Обновить env:
```bash
bash aiflow-v2/rollout/pl108_enable_limited_rollout.sh \
  --env-file .flow/config/flow.env \
  --allow-task PL-105
```

## Step 2
Проверить итоговые ключи:
```bash
rg '^FLOW_V2_(ROLLOUT_MODE|ALLOWED_TASK_IDS|EMERGENCY_ON_BREACH|MAX_EXECUTIONS_PER_TASK|MAX_TOKEN_USAGE_PER_TASK|MAX_ESTIMATED_COST_PER_TASK)=' .flow/config/flow.env
```

Ожидается:
- `FLOW_V2_ROLLOUT_MODE=limited`
- `FLOW_V2_ALLOWED_TASK_IDS=<csv>`

## Step 3
Перед фактическим запуском automation оставить:
- `control_mode = SAFE`

## Step 4
Первый limited run включать только после явного operator decision.
