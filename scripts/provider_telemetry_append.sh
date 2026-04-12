#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 7 || $# -gt 8 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <module> <requested-provider> <effective-provider> <outcome> <request-id> [error-class]"
  exit 1
fi

task_id="$1"
issue_number="$2"
module_name="$3"
requested_provider="$4"
effective_provider="$5"
outcome="$6"
request_id="$7"
error_class="${8:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
mkdir -p "$CODEX_DIR"

LEDGER_FILE="${CODEX_DIR}/provider_telemetry.jsonl"

latency_ms="${PROVIDER_TELEMETRY_LATENCY_MS:-null}"
token_usage="${PROVIDER_TELEMETRY_TOKEN_USAGE:-null}"
estimated_cost="${PROVIDER_TELEMETRY_ESTIMATED_COST:-null}"
fallback_used="${PROVIDER_TELEMETRY_FALLBACK_USED:-0}"
fallback_from_provider="${PROVIDER_TELEMETRY_FALLBACK_FROM_PROVIDER:-}"
misroute="${PROVIDER_TELEMETRY_MISROUTE:-0}"
error_message="${PROVIDER_TELEMETRY_ERROR_MESSAGE:-}"
decision_reason="${PROVIDER_TELEMETRY_DECISION_REASON:-}"
timeout_ms="${PROVIDER_TELEMETRY_TIMEOUT_MS:-null}"
budget_key="${PROVIDER_TELEMETRY_BUDGET_KEY:-}"
compare_mode="${PROVIDER_TELEMETRY_COMPARE_MODE:-}"
primary_provider="${PROVIDER_TELEMETRY_PRIMARY_PROVIDER:-}"
shadow_provider="${PROVIDER_TELEMETRY_SHADOW_PROVIDER:-}"
schema_valid_primary="${PROVIDER_TELEMETRY_SCHEMA_VALID_PRIMARY:-}"
schema_valid_shadow="${PROVIDER_TELEMETRY_SCHEMA_VALID_SHADOW:-}"
profile_match="${PROVIDER_TELEMETRY_PROFILE_MATCH:-}"
target_files_match="${PROVIDER_TELEMETRY_TARGET_FILES_MATCH:-}"
target_files_drift_kind="${PROVIDER_TELEMETRY_TARGET_FILES_DRIFT_KIND:-}"
target_files_drift_tolerated="${PROVIDER_TELEMETRY_TARGET_FILES_DRIFT_TOLERATED:-}"
human_needed_match="${PROVIDER_TELEMETRY_HUMAN_NEEDED_MATCH:-}"
confidence_delta="${PROVIDER_TELEMETRY_CONFIDENCE_DELTA:-null}"
compare_summary="${PROVIDER_TELEMETRY_COMPARE_SUMMARY:-}"
publish_decision="${PROVIDER_TELEMETRY_PUBLISH_DECISION:-0}"

if ! [[ "$latency_ms" =~ ^[0-9]+$ ]]; then
  latency_ms="null"
fi
if ! [[ "$token_usage" =~ ^[0-9]+$ ]]; then
  token_usage="null"
fi
if ! [[ "$estimated_cost" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  estimated_cost="null"
fi
if ! [[ "$timeout_ms" =~ ^[0-9]+$ ]]; then
  timeout_ms="null"
fi
if ! [[ "$confidence_delta" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  confidence_delta="null"
fi

json_bool_or_null() {
  local value="${1:-}"
  case "$value" in
    1|true|TRUE|yes|YES) printf 'true' ;;
    0|false|FALSE|no|NO) printf 'false' ;;
    *) printf 'null' ;;
  esac
}

jq -nc \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg requestId "$request_id" \
  --arg taskId "$task_id" \
  --argjson issueNumber "$issue_number" \
  --arg moduleName "$module_name" \
  --arg requestedProvider "$requested_provider" \
  --arg effectiveProvider "$effective_provider" \
  --arg outcome "$outcome" \
  --arg fallbackFromProvider "$fallback_from_provider" \
  --arg decisionReason "$decision_reason" \
  --arg budgetKey "$budget_key" \
  --arg compareMode "$compare_mode" \
  --arg primaryProvider "$primary_provider" \
  --arg shadowProvider "$shadow_provider" \
  --arg compareSummary "$compare_summary" \
  --arg targetFilesDriftKind "$target_files_drift_kind" \
  --arg errorClass "$error_class" \
  --arg errorMessage "$error_message" \
  --argjson latencyMs "$latency_ms" \
  --argjson timeoutMs "$timeout_ms" \
  --argjson tokenUsage "$token_usage" \
  --argjson estimatedCost "$estimated_cost" \
  --argjson confidenceDelta "$confidence_delta" \
  --argjson fallbackUsed "$([[ "$fallback_used" == "1" ]] && printf 'true' || printf 'false')" \
  --argjson misroute "$([[ "$misroute" == "1" ]] && printf 'true' || printf 'false')" \
  --argjson schemaValidPrimary "$(json_bool_or_null "$schema_valid_primary")" \
  --argjson schemaValidShadow "$(json_bool_or_null "$schema_valid_shadow")" \
  --argjson profileMatch "$(json_bool_or_null "$profile_match")" \
  --argjson targetFilesMatch "$(json_bool_or_null "$target_files_match")" \
  --argjson targetFilesDriftTolerated "$(json_bool_or_null "$target_files_drift_tolerated")" \
  --argjson humanNeededMatch "$(json_bool_or_null "$human_needed_match")" \
  --argjson publishDecision "$(json_bool_or_null "$publish_decision")" \
  '{
    ts:$ts,
    requestId:$requestId,
    taskId:$taskId,
    issueNumber:$issueNumber,
    "module":$moduleName,
    requestedProvider:$requestedProvider,
    effectiveProvider:$effectiveProvider,
    outcome:$outcome,
    fallbackUsed:$fallbackUsed,
    fallbackFromProvider:(if $fallbackFromProvider == "" then null else $fallbackFromProvider end),
    decisionReason:(if $decisionReason == "" then null else $decisionReason end),
    timeoutMs:$timeoutMs,
    budgetKey:(if $budgetKey == "" then null else $budgetKey end),
    compareMode:(if $compareMode == "" then null else $compareMode end),
    primaryProvider:(if $primaryProvider == "" then null else $primaryProvider end),
    shadowProvider:(if $shadowProvider == "" then null else $shadowProvider end),
    schemaValidPrimary:$schemaValidPrimary,
    schemaValidShadow:$schemaValidShadow,
    profileMatch:$profileMatch,
    targetFilesMatch:$targetFilesMatch,
    targetFilesDriftKind:(if $targetFilesDriftKind == "" then null else $targetFilesDriftKind end),
    targetFilesDriftTolerated:$targetFilesDriftTolerated,
    humanNeededMatch:$humanNeededMatch,
    confidenceDelta:$confidenceDelta,
    compareSummary:(if $compareSummary == "" then null else $compareSummary end),
    publishDecision:$publishDecision,
    errorClass:(if $errorClass == "" then null else $errorClass end),
    errorMessage:(if $errorMessage == "" then null else $errorMessage end),
    latencyMs:$latencyMs,
    tokenUsage:$tokenUsage,
    estimatedCost:$estimatedCost,
    misroute:$misroute
  }' >> "$LEDGER_FILE"

echo "PROVIDER_TELEMETRY_RECORDED=1"
echo "PROVIDER_TELEMETRY_REQUEST_ID=${request_id}"
echo "PROVIDER_TELEMETRY_MODULE=${module_name}"
echo "PROVIDER_TELEMETRY_PROVIDER=${effective_provider}"
echo "PROVIDER_TELEMETRY_OUTCOME=${outcome}"
