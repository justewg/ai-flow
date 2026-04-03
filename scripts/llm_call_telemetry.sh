#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <phase> <call-index> <prompt-file> <response-file> <call-log-file>"
  exit 1
fi

task_id="$1"
issue_number="$2"
phase="$3"
call_index="$4"
prompt_file="$5"
response_file="$6"
call_log_file="$7"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
llm_calls_file="$(task_worktree_llm_calls_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
budget_file="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
mkdir -p "$(dirname "$llm_calls_file")"

prompt_chars=0
response_chars=0
[[ -f "$prompt_file" ]] && prompt_chars="$(wc -c < "$prompt_file" | tr -d '[:space:]')"
[[ -f "$response_file" ]] && response_chars="$(wc -c < "$response_file" | tr -d '[:space:]')"

prompt_tokens_estimate=$(( (prompt_chars + 3) / 4 ))
response_tokens_estimate=$(( (response_chars + 3) / 4 ))
total_tokens=""
if [[ -f "$call_log_file" ]]; then
  total_tokens="$(awk '/^tokens used$/{getline; gsub(/,/, "", $0); print $0}' "$call_log_file" | tail -n1)"
fi
if [[ -z "$total_tokens" ]]; then
  total_tokens=$(( prompt_tokens_estimate + response_tokens_estimate ))
fi

input_tokens="$prompt_tokens_estimate"
if [[ "$total_tokens" =~ ^[0-9]+$ ]] && (( total_tokens > response_tokens_estimate )); then
  input_tokens=$(( total_tokens - response_tokens_estimate ))
fi

output_tokens="$response_tokens_estimate"
cost_mode="unavailable"
estimated_cost="null"
input_rate="${EXECUTOR_INPUT_COST_PER_1K:-}"
output_rate="${EXECUTOR_OUTPUT_COST_PER_1K:-}"
if [[ "$input_rate" =~ ^[0-9]+([.][0-9]+)?$ && "$output_rate" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  estimated_cost="$(awk -v in_tokens="$input_tokens" -v out_tokens="$output_tokens" -v in_rate="$input_rate" -v out_rate="$output_rate" 'BEGIN { printf "%.6f", ((in_tokens / 1000.0) * in_rate) + ((out_tokens / 1000.0) * out_rate) }')"
  cost_mode="env_rates"
fi

jq -nc \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg phase "$phase" \
  --argjson callIndex "$call_index" \
  --arg promptFile "$prompt_file" \
  --arg responseFile "$response_file" \
  --arg logFile "$call_log_file" \
  --argjson inputTokens "$input_tokens" \
  --argjson outputTokens "$output_tokens" \
  --argjson totalTokens "$total_tokens" \
  --arg costEstimateMode "$cost_mode" \
  --argjson estimatedCostUsd "$estimated_cost" \
  '{
    ts:$ts,
    taskId:$taskId,
    issueNumber:$issueNumber,
    phase:$phase,
    callIndex:$callIndex,
    promptFile:$promptFile,
    responseFile:$responseFile,
    logFile:$logFile,
    inputTokens:$inputTokens,
    outputTokens:$outputTokens,
    totalTokens:$totalTokens,
    costEstimateMode:$costEstimateMode,
    estimatedCostUsd:$estimatedCostUsd
  }' >> "$llm_calls_file"

if [[ ! -f "$budget_file" ]]; then
  jq -nc \
    --arg taskId "$task_id" \
    --arg issueNumber "$issue_number" \
    '{taskId:$taskId, issueNumber:$issueNumber, profile:"standard", callCount:0, totalInputTokens:0, totalOutputTokens:0, totalTokens:0, thresholdTokens:null, estimatedCostUsd:null, costEstimateMode:"unavailable", enforceProfileBreach:false, status:"telemetry_only", profileBreach:false}' > "$budget_file"
fi

tmp_file="$(mktemp "$(dirname "$budget_file")/execution_budget.XXXXXX")"
jq \
  --argjson inputTokens "$input_tokens" \
  --argjson outputTokens "$output_tokens" \
  --argjson totalTokens "$total_tokens" \
  --arg costEstimateMode "$cost_mode" \
  --argjson estimatedCostUsd "$estimated_cost" \
  '
    .callCount = ((.callCount // 0) + 1)
    | .totalInputTokens = ((.totalInputTokens // 0) + $inputTokens)
    | .totalOutputTokens = ((.totalOutputTokens // 0) + $outputTokens)
    | .totalTokens = ((.totalTokens // 0) + $totalTokens)
    | .costEstimateMode = (if $costEstimateMode == "env_rates" then "env_rates" else (.costEstimateMode // "unavailable") end)
    | .estimatedCostUsd =
        (if $estimatedCostUsd == null then .estimatedCostUsd
         else ((.estimatedCostUsd // 0) + $estimatedCostUsd)
         end)
    | .profileBreach =
        (((.callCount // 0) > (.maxCalls // 999999)) or ((.thresholdTokens != null) and ((.totalTokens // 0) > .thresholdTokens)))
    | .status =
        (if .profileBreach then "profile_breach_observed" else "ok" end)
  ' "$budget_file" > "$tmp_file"
mv "$tmp_file" "$budget_file"

echo "LLM_CALL_TELEMETRY_RECORDED=1"
echo "LLM_CALL_INDEX=${call_index}"
echo "LLM_CALL_TOTAL_TOKENS=${total_tokens}"
echo "LLM_BUDGET_FILE=${budget_file}"
