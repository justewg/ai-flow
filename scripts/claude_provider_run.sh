#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLAUDE_RUNNER="${TOOLKIT_ROOT}/tools/providers/claude/run_claude_provider.mjs"
NODE_BIN="${NODE_BIN:-node}"
CLAUDE_PROVIDER_AUTH_COOLDOWN_SEC="${CLAUDE_PROVIDER_AUTH_COOLDOWN_SEC:-300}"

source "${SCRIPT_DIR}/env/bootstrap.sh"

build_cached_auth_error() {
  local request_id="$1"
  local task_id="$2"
  local module="$3"
  local error_class="$4"
  local error_message="$5"

  jq -nc \
    --arg requestId "$request_id" \
    --arg taskId "$task_id" \
    --arg moduleName "$module" \
    --arg errorClass "$error_class" \
    --arg errorMessage "$error_message" \
    '{
      requestId:$requestId,
      taskId:$taskId,
      "module":$moduleName,
      provider:"claude",
      outcome:"error",
      outputText:null,
      structuredOutput:{},
      errorClass:$errorClass,
      errorMessage:$errorMessage,
      latencyMs:0,
      tokenUsage:null,
      estimatedCost:null,
      fallbackFromProvider:null,
      meta:{cachedAuthCooldown:true}
    }'
}

read_cached_auth_error_if_hot() {
  local health_file="$1"
  local task_id="$2"
  local module="$3"
  local now_epoch="$4"

  [[ -f "$health_file" ]] || return 1

  local last_error_class last_error_message last_failure_epoch age
  last_error_class="$(jq -r '.lastErrorClass // empty' "$health_file" 2>/dev/null || true)"
  last_error_message="$(jq -r '.lastErrorMessage // empty' "$health_file" 2>/dev/null || true)"
  last_failure_epoch="$(jq -r '.lastFailureEpoch // empty' "$health_file" 2>/dev/null || true)"
  [[ -n "$last_error_class" && -n "$last_failure_epoch" ]] || return 1
  [[ "$last_error_class" == "auth_missing" || "$last_error_class" == "auth_forbidden" ]] || return 1
  [[ "$last_failure_epoch" =~ ^[0-9]+$ ]] || return 1

  age=$(( now_epoch - last_failure_epoch ))
  if (( age < 0 )); then
    age=0
  fi
  if (( age < CLAUDE_PROVIDER_AUTH_COOLDOWN_SEC )); then
    build_cached_auth_error \
      "claude_cached_auth:${module}:${task_id}:${now_epoch}" \
      "$task_id" \
      "$module" \
      "$last_error_class" \
      "Claude auth cooldown active (${age}s < ${CLAUDE_PROVIDER_AUTH_COOLDOWN_SEC}s): ${last_error_message}"
    return 0
  fi

  return 1
}

write_provider_health() {
  local health_file="$1"
  local payload_json="$2"
  local now_epoch="$3"

  local outcome error_class error_message
  outcome="$(printf '%s' "$payload_json" | jq -r '.outcome // empty' 2>/dev/null || true)"
  error_class="$(printf '%s' "$payload_json" | jq -r '.errorClass // empty' 2>/dev/null || true)"
  error_message="$(printf '%s' "$payload_json" | jq -r '.errorMessage // empty' 2>/dev/null || true)"

  mkdir -p "$(dirname "$health_file")"

  if [[ "$outcome" == "success" ]]; then
    jq -nc \
      --arg lastStatus "healthy" \
      --arg lastSuccessAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --argjson lastSuccessEpoch "$now_epoch" \
      '{
        lastStatus:$lastStatus,
        lastSuccessAt:$lastSuccessAt,
        lastSuccessEpoch:$lastSuccessEpoch,
        lastErrorClass:null,
        lastErrorMessage:null,
        lastFailureEpoch:null
      }' > "$health_file"
    return 0
  fi

  if [[ "$error_class" == "auth_missing" || "$error_class" == "auth_forbidden" ]]; then
    jq -nc \
      --arg lastStatus "auth_error" \
      --arg lastErrorClass "$error_class" \
      --arg lastErrorMessage "$error_message" \
      --arg lastFailureAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --argjson lastFailureEpoch "$now_epoch" \
      --argjson cooldownSec "$CLAUDE_PROVIDER_AUTH_COOLDOWN_SEC" \
      '{
        lastStatus:$lastStatus,
        lastErrorClass:$lastErrorClass,
        lastErrorMessage:$lastErrorMessage,
        lastFailureAt:$lastFailureAt,
        lastFailureEpoch:$lastFailureEpoch,
        cooldownSec:$cooldownSec
      }' > "$health_file"
  fi
}

clear_provider_health() {
  local health_file="$1"
  rm -f "$health_file"
}

main() {
  local state_dir health_file now_epoch cached_json tmp_output rc payload_json task_id module runner_home
  state_dir="$(codex_resolve_state_dir)"
  health_file="${state_dir}/claude_provider_health.json"
  now_epoch="$(date +%s)"
  runner_home="${AI_FLOW_RUNTIME_HOME:-${HOME:-}}"

  task_id=""
  module=""
  local argv=("$@")
  local index=0
  while (( index < ${#argv[@]} )); do
    if [[ "${argv[$index]}" == "--task-id" ]] && (( index + 1 < ${#argv[@]} )); then
      task_id="${argv[$((index + 1))]}"
    elif [[ "${argv[$index]}" == "--module" ]] && (( index + 1 < ${#argv[@]} )); then
      module="${argv[$((index + 1))]}"
    fi
    index=$((index + 1))
  done

  if [[ "${CLAUDE_PROVIDER_BYPASS_AUTH_COOLDOWN:-0}" != "1" ]] && cached_json="$(read_cached_auth_error_if_hot "$health_file" "$task_id" "$module" "$now_epoch")"; then
    printf '%s\n' "$cached_json"
    exit 0
  fi

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/claude-provider-run.XXXXXX.json")"
  rc=0
  if ! HOME="$runner_home" "$NODE_BIN" "$CLAUDE_RUNNER" \
    --toolkit-root "$TOOLKIT_ROOT" \
    "$@" >"$tmp_output"; then
    rc=$?
  fi

  payload_json="$(cat "$tmp_output" 2>/dev/null || true)"
  rm -f "$tmp_output"

  if [[ -z "$payload_json" ]]; then
    payload_json="$(
      jq -nc \
        --arg requestId "claude_runner_shell_failure:${module}:${task_id}:${now_epoch}" \
        --arg taskId "$task_id" \
        --arg moduleName "$module" \
        --arg errorMessage "claude runner exited without JSON payload (rc=${rc})" \
        '{
          requestId:$requestId,
          taskId:$taskId,
          "module":$moduleName,
          provider:"claude",
          outcome:"error",
          outputText:null,
          structuredOutput:{},
          errorClass:"runner_shell_failure",
          errorMessage:$errorMessage,
          latencyMs:null,
          tokenUsage:null,
          estimatedCost:null,
          fallbackFromProvider:null,
          meta:{}
        }'
    )"
  fi

  write_provider_health "$health_file" "$payload_json" "$now_epoch"
  printf '%s\n' "$payload_json"
  exit 0
}

main "$@"
