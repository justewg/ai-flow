#!/usr/bin/env bash

# shellcheck shell=bash

graphql_audit_enabled() {
  local raw="${GRAPHQL_AUDIT_ENABLED:-1}"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

graphql_audit_log_file() {
  local log_dir="${RUNTIME_LOG_DIR:-}"
  if [[ -z "$log_dir" ]]; then
    log_dir="$(codex_resolve_flow_runtime_log_dir)"
  fi
  mkdir -p "$log_dir"
  printf '%s' "${GRAPHQL_AUDIT_LOG_FILE:-${log_dir}/graphql_audit.log}"
}

graphql_audit_sanitize() {
  local value="${1:-}"
  printf '%s' "$value" | tr '\n' ' ' | tr '\t' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

graphql_audit_now_epoch() {
  date +%s
}

graphql_audit_outcome_from_result() {
  local rc="$1"
  local text="${2:-}"
  local normalized

  if [[ "$rc" -eq 0 ]]; then
    printf '%s' "success"
    return 0
  fi

  normalized="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$normalized" | grep -Eq 'api rate limit already exceeded|graphql_rate_limit|rate limit exceeded|secondary rate limit|exceeded a secondary rate limit'; then
    printf '%s' "rate_limit"
  elif printf '%s' "$normalized" | grep -Eq 'bad credentials|http 401|status[^[:alnum:]]*401|requires authentication|resource not accessible by personal access token|invalid token|unauthorized'; then
    printf '%s' "auth"
  elif printf '%s' "$normalized" | grep -Eq 'excessive_pagination|exceeds the `first` limit of 100 records'; then
    printf '%s' "pagination"
  else
    printf '%s' "error"
  fi
}

graphql_audit_emit() {
  local caller="$1"
  local stage="$2"
  local mode="$3"
  local query_family="$4"
  local cacheability="$5"
  local outcome="$6"
  local detail="${7:-}"
  local duration_sec="${8:-0}"
  local rc="${9:-0}"
  local log_file now_utc current_task_id current_issue_number current_item_id

  graphql_audit_enabled || return 0

  log_file="$(graphql_audit_log_file)"
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  current_task_id="${GRAPHQL_AUDIT_TASK_ID:-${task_id-}}"
  current_issue_number="${GRAPHQL_AUDIT_ISSUE_NUMBER:-${issue_number-}}"
  current_item_id="${GRAPHQL_AUDIT_ITEM_ID:-${item_id-}}"

  printf '%s\tCALLER=%s\tSTAGE=%s\tMODE=%s\tQUERY_FAMILY=%s\tCACHEABILITY=%s\tOUTCOME=%s\tRC=%s\tDURATION_SEC=%s' \
    "$now_utc" \
    "$(graphql_audit_sanitize "$caller")" \
    "$(graphql_audit_sanitize "$stage")" \
    "$(graphql_audit_sanitize "$mode")" \
    "$(graphql_audit_sanitize "$query_family")" \
    "$(graphql_audit_sanitize "$cacheability")" \
    "$(graphql_audit_sanitize "$outcome")" \
    "$(graphql_audit_sanitize "$rc")" \
    "$(graphql_audit_sanitize "$duration_sec")" \
    >> "$log_file"

  [[ -n "$current_task_id" ]] && printf '\tTASK_ID=%s' "$(graphql_audit_sanitize "$current_task_id")" >> "$log_file"
  [[ -n "$current_issue_number" ]] && printf '\tISSUE_NUMBER=%s' "$(graphql_audit_sanitize "$current_issue_number")" >> "$log_file"
  [[ -n "$current_item_id" ]] && printf '\tITEM_ID=%s' "$(graphql_audit_sanitize "$current_item_id")" >> "$log_file"
  [[ -n "$detail" ]] && printf '\tDETAIL=%s' "$(graphql_audit_sanitize "$detail")" >> "$log_file"
  printf '\n' >> "$log_file"
}

graphql_audit_capture() {
  local caller="$1"
  local stage="$2"
  local mode="$3"
  local query_family="$4"
  local cacheability="$5"
  local detail="${6:-}"
  shift 6

  local start_epoch end_epoch duration_sec output rc outcome
  start_epoch="$(graphql_audit_now_epoch)"
  if output="$("$@" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  end_epoch="$(graphql_audit_now_epoch)"
  duration_sec=$(( end_epoch - start_epoch ))
  outcome="$(graphql_audit_outcome_from_result "$rc" "$output")"
  graphql_audit_emit "$caller" "$stage" "$mode" "$query_family" "$cacheability" "$outcome" "$detail" "$duration_sec" "$rc"

  if [[ "$rc" -eq 0 ]]; then
    printf '%s' "$output"
  else
    printf '%s' "$output" >&2
  fi
  return "$rc"
}
