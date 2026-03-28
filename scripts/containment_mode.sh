#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$CODEX_DIR" "$STATE_TMP_DIR"

MODE_FILE="${CODEX_DIR}/flow_control_mode.txt"
REASON_FILE="${CODEX_DIR}/flow_control_reason.txt"
CHANGED_AT_FILE="${CODEX_DIR}/flow_control_changed_at.txt"
INCIDENT_LEDGER_FILE="${CODEX_DIR}/incident_ledger.jsonl"

normalize_mode() {
  printf '%s' "${1:-AUTO}" | tr '[:lower:]' '[:upper:]'
}

current_mode() {
  local mode
  if [[ -s "$MODE_FILE" ]]; then
    mode="$(<"$MODE_FILE")"
  else
    mode="AUTO"
  fi
  mode="$(normalize_mode "$mode")"
  case "$mode" in
    AUTO|SAFE|EMERGENCY_STOP) printf '%s' "$mode" ;;
    *) printf 'AUTO' ;;
  esac
}

current_reason() {
  if [[ -s "$REASON_FILE" ]]; then
    cat "$REASON_FILE"
  fi
}

append_incident_json() {
  local event_type="$1"
  local message="$2"
  local mode="$3"
  jq -nc \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg type "$event_type" \
    --arg mode "$mode" \
    --arg msg "$message" \
    '{ts:$ts,type:$type,mode:$mode,message:$msg}' >> "$INCIDENT_LEDGER_FILE"
}

usage() {
  cat <<'EOF'
Usage:
  containment_mode.sh get [--raw]
  containment_mode.sh set <AUTO|SAFE|EMERGENCY_STOP> [reason...]
  containment_mode.sh check-expensive
EOF
}

cmd="${1:-get}"

case "$cmd" in
  get)
    if [[ "${2:-}" == "--raw" ]]; then
      current_mode
      exit 0
    fi
    printf 'CONTROL_MODE=%s\n' "$(current_mode)"
    printf 'CONTROL_REASON=%s\n' "$(current_reason)"
    if [[ -s "$CHANGED_AT_FILE" ]]; then
      printf 'CONTROL_CHANGED_AT=%s\n' "$(<"$CHANGED_AT_FILE")"
    fi
    ;;
  set)
    if [[ $# -lt 2 ]]; then
      usage
      exit 1
    fi
    mode="$(normalize_mode "$2")"
    shift 2
    case "$mode" in
      AUTO|SAFE|EMERGENCY_STOP) ;;
      *)
        echo "Unsupported mode: $mode"
        exit 1
        ;;
    esac
    reason="${*:-manual update}"
    printf '%s\n' "$mode" > "$MODE_FILE"
    printf '%s\n' "$reason" > "$REASON_FILE"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$CHANGED_AT_FILE"
    append_incident_json "control_mode_changed" "$reason" "$mode"
    printf 'CONTROL_MODE_SET=%s\n' "$mode"
    printf 'CONTROL_REASON=%s\n' "$reason"
    ;;
  check-expensive)
    mode="$(current_mode)"
    reason="$(current_reason)"
    printf 'CONTROL_MODE=%s\n' "$mode"
    printf 'CONTROL_REASON=%s\n' "$reason"
    if [[ "$mode" == "AUTO" ]]; then
      echo "CONTROL_ALLOW_EXPENSIVE=1"
    else
      echo "CONTROL_ALLOW_EXPENSIVE=0"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
