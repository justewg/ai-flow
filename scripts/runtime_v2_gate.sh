#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <gate-name> [gate-profile]"
  exit 1
fi

task_id="$1"
issue_number="$2"
gate_name="$3"
gate_profile="${4:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"
V2_STORE_DIR="${V2_STATE_DIR}/store"
mkdir -p "$V2_STORE_DIR"

repo="${FLOW_GITHUB_REPO:-unknown/repo}"
rollout_mode="$(codex_resolve_config_value "FLOW_V2_ROLLOUT_MODE" "shadow")"
allowed_task_ids="$(codex_resolve_config_value "FLOW_V2_ALLOWED_TASK_IDS" "")"
max_executions_per_task="$(codex_resolve_config_value "FLOW_V2_MAX_EXECUTIONS_PER_TASK" "3")"
max_token_usage_per_task="$(codex_resolve_config_value "FLOW_V2_MAX_TOKEN_USAGE_PER_TASK" "60000")"
max_estimated_cost_per_task="$(codex_resolve_config_value "FLOW_V2_MAX_ESTIMATED_COST_PER_TASK" "25")"
emergency_on_breach="$(codex_resolve_config_value "FLOW_V2_EMERGENCY_ON_BREACH" "1")"

side_effect_class="state_only"
expensive="1"
stale_check="0"

case "$gate_profile" in
  daemon_claim)
    side_effect_class="state_only"
    expensive="1"
    stale_check="0"
    ;;
  executor_start)
    side_effect_class="expensive_ai"
    expensive="1"
    stale_check="0"
    ;;
  watchdog_recover)
    side_effect_class="state_only"
    expensive="1"
    stale_check="1"
    ;;
  default)
    ;;
  *)
    echo "Unsupported gate profile: ${gate_profile}" >&2
    exit 1
    ;;
esac

gate_json="$(node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_gate.js" \
  --legacy-state-dir "$CODEX_DIR" \
  --store-dir "$V2_STORE_DIR" \
  --repo "$repo" \
  --task-id "$task_id" \
  --issue-number "$issue_number" \
  --gate-name "$gate_name" \
  --rollout-mode "$rollout_mode" \
  --allowed-task-ids "$allowed_task_ids" \
  --side-effect-class "$side_effect_class" \
  --expensive "$expensive" \
  --stale-check "$stale_check" \
  --max-executions-per-task "$max_executions_per_task" \
  --max-token-usage-per-task "$max_token_usage_per_task" \
  --max-estimated-cost-per-task "$max_estimated_cost_per_task" \
  --emergency-on-breach "$emergency_on_breach")"

control_sync_out="$(
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_sync_control_mode.sh" 2>&1
)"

printf '%s\n' "$gate_json"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<< "$control_sync_out"
echo "RUNTIME_V2_GATE_STATUS=$(printf '%s' "$gate_json" | jq -r '.status // "unknown"')"
echo "RUNTIME_V2_GATE_REASON=$(printf '%s' "$gate_json" | jq -r '.reason // ""')"
echo "RUNTIME_V2_GATE_NAME=$gate_name"
echo "RUNTIME_V2_GATE_PROFILE=$gate_profile"
echo "RUNTIME_V2_GATE_TASK_ID=$task_id"
