#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly PUBLIC_ROOT="/etc/ai-flow/public"
readonly PROJECT_PUBLIC_ROOT="${PUBLIC_ROOT}/projects"
readonly DIAGNOSTICS_ROOT="/var/lib/ai-flow/diagnostics"
readonly AUDIT_LOG="/var/log/ai-flow/remote-agent-v2.log"
readonly DEFAULT_PROFILE="default"
readonly DEFAULT_INTERVAL_SEC="15"
readonly DEFAULT_TTL_SEC="30"
readonly DEFAULT_LINES="120"
readonly MAX_LINES="200"
readonly MAX_OUTPUT_BYTES="131072"
readonly MAX_SNAPSHOT_BYTES="262144"

usage() {
  cat <<'EOF'
Usage:
  remote_agent_v2_helper.sh --dispatch <probe> [--profile <profile>] [--lines <N>]

Fixed read-only helper for Remote Agent v2.
EOF
}

now_epoch() {
  date +%s
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

monotonic_ms() {
  date +%s%3N
}

log_event() {
  local event="$1"
  local profile="$2"
  local probe="$3"
  local exit_code="$4"
  local duration_ms="$5"
  local output_bytes="$6"
  local detail="$7"

  mkdir -p "$(dirname "$AUDIT_LOG")"
  touch "$AUDIT_LOG"
  chmod 0640 "$AUDIT_LOG"
  printf '%s event=%s profile=%s probe=%s exit_code=%s duration_ms=%s output_bytes=%s user=%s ssh_connection="%s" detail="%s"\n' \
    "$(now_utc)" \
    "$event" \
    "$profile" \
    "$probe" \
    "$exit_code" \
    "$duration_ms" \
    "$output_bytes" \
    "${SUDO_USER:-${USER:-unknown}}" \
    "${SSH_CONNECTION:-}" \
    "$(printf '%s' "$detail" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/"/\\"/g')" >> "$AUDIT_LOG"
}

read_env_key() {
  local env_file="$1"
  local key="$2"
  [[ -f "$env_file" ]] || return 0
  awk -F= -v key="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 == key {
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
  ' "$env_file"
}

emit_json() {
  printf '%s\n' "$1"
}

emit_degraded_json() {
  local profile="$1"
  local probe="$2"
  local detail_json="$3"
  jq -cn \
    --arg profile "$profile" \
    --arg probe "$probe" \
    --arg generated_at "$(now_utc)" \
    --argjson detail "$detail_json" \
    '{
      status: "degraded",
      profile: $profile,
      probe: $probe,
      generated_at: $generated_at
    } + $detail'
}

validate_profile() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

validate_probe() {
  case "$1" in
    runtime_snapshot_v2|ops_health_v2|runtime_log_tail_v2|compose_contract_metadata_v2|nginx_ingress_metadata_v2|workspace_git_metadata_v2)
      return 0
      ;;
  esac
  return 1
}

snapshot_filename_for_probe() {
  case "$1" in
    runtime_snapshot_v2|ops_health_v2) printf '%s' "runtime_snapshot.json" ;;
    runtime_log_tail_v2) printf '%s' "runtime_log_tail.json" ;;
    compose_contract_metadata_v2) printf '%s' "compose_metadata.json" ;;
    nginx_ingress_metadata_v2) printf '%s' "ingress_metadata.json" ;;
    workspace_git_metadata_v2) printf '%s' "workspace_metadata.json" ;;
    *) return 1 ;;
  esac
}

file_size_bytes() {
  local path="$1"
  if stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    stat -c %s "$path"
  fi
}

file_mtime_epoch() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

project_public_env_for_profile() {
  printf '%s/%s.env' "$PROJECT_PUBLIC_ROOT" "$1"
}

diagnostics_dir_for_profile() {
  local profile="$1"
  local env_file
  env_file="$(project_public_env_for_profile "$profile")"
  local value
  value="$(read_env_key "$env_file" "AI_FLOW_DIAGNOSTICS_DIR" || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s/%s' "$DIAGNOSTICS_ROOT" "$profile"
  fi
}

publisher_interval_for_profile() {
  local profile="$1"
  local env_file
  env_file="$(project_public_env_for_profile "$profile")"
  local value
  value="$(read_env_key "$env_file" "AI_FLOW_DIAGNOSTICS_PUBLISH_INTERVAL_SEC" || true)"
  if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 )); then
    printf '%s' "$value"
  else
    printf '%s' "$DEFAULT_INTERVAL_SEC"
  fi
}

snapshot_ttl_for_profile() {
  local profile="$1"
  local interval
  interval="$(publisher_interval_for_profile "$profile")"
  printf '%s' "$(( interval * 2 ))"
}

stale_payload() {
  local profile="$1"
  local probe="$2"
  local age="$3"
  local ttl="$4"
  emit_degraded_json "$profile" "$probe" "$(jq -cn --argjson age "$age" --argjson ttl "$ttl" '{snapshot_stale:true,snapshot_age_sec:$age,snapshot_ttl_sec:$ttl}')"
}

missing_payload() {
  local profile="$1"
  local probe="$2"
  emit_degraded_json "$profile" "$probe" '{"snapshot_missing":true}'
}

oversize_payload() {
  local profile="$1"
  local probe="$2"
  local size="$3"
  emit_degraded_json "$profile" "$probe" "$(jq -cn --argjson size "$size" --argjson limit "$MAX_SNAPSHOT_BYTES" '{snapshot_oversize:true,snapshot_size_bytes:$size,snapshot_size_limit_bytes:$limit}')"
}

invalid_json_payload() {
  local profile="$1"
  local probe="$2"
  emit_degraded_json "$profile" "$probe" '{"snapshot_invalid_json":true}'
}

read_snapshot_payload() {
  local probe="$1"
  local profile="$2"
  local lines="$3"
  local diagnostics_dir snapshot_file ttl age size snapshot_json
  diagnostics_dir="$(diagnostics_dir_for_profile "$profile")"
  snapshot_file="${diagnostics_dir}/$(snapshot_filename_for_probe "$probe")"

  if [[ ! -f "$snapshot_file" ]]; then
    missing_payload "$profile" "$probe"
    return 0
  fi

  size="$(file_size_bytes "$snapshot_file")"
  if ! [[ "$size" =~ ^[0-9]+$ ]]; then
    size=0
  fi
  if (( size > MAX_SNAPSHOT_BYTES )); then
    oversize_payload "$profile" "$probe" "$size"
    return 0
  fi

  ttl="$(snapshot_ttl_for_profile "$profile")"
  age="$(( $(now_epoch) - $(file_mtime_epoch "$snapshot_file") ))"
  if (( age > ttl )); then
    stale_payload "$profile" "$probe" "$age" "$ttl"
    return 0
  fi

  if ! snapshot_json="$(jq -c . "$snapshot_file" 2>/dev/null)"; then
    invalid_json_payload "$profile" "$probe"
    return 0
  fi

  case "$probe" in
    runtime_log_tail_v2)
      jq -c \
        --argjson lines "$lines" \
        --argjson age "$age" \
        '.snapshot_age_sec = $age
         | .snapshot_stale = false
         | .logs |= with_entries(
             if (.value | type) == "array" then
               .value |= .[-$lines:]
             else
               .
             end
           )' <<< "$snapshot_json"
      ;;
    ops_health_v2)
      jq -c \
        --argjson age "$age" \
        '{
          schema_version,
          profile,
          published_at,
          publisher_interval_sec,
          snapshot_ttl_sec,
          snapshot_age_sec: $age,
          snapshot_stale: false,
          service_health: .health,
          runtime_status: .status.overall_status,
          daemon_state: .status.daemon.state,
          watchdog_state: .status.watchdog.state
        }' <<< "$snapshot_json"
      ;;
    *)
      jq -c --argjson age "$age" '.snapshot_age_sec = $age | .snapshot_stale = false' <<< "$snapshot_json"
      ;;
  esac
}

main() {
  local mode=""
  local probe=""
  local profile="$DEFAULT_PROFILE"
  local lines="$DEFAULT_LINES"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      --dispatch)
        [[ $# -ge 2 ]] || { echo "Missing value for --dispatch" >&2; exit 1; }
        mode="dispatch"
        probe="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
        profile="$2"
        shift 2
        ;;
      --lines)
        [[ $# -ge 2 ]] || { echo "Missing value for --lines" >&2; exit 1; }
        lines="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ "$(id -u)" -eq 0 ]] || {
    echo "This helper must run as root." >&2
    exit 1
  }

  [[ "$mode" == "dispatch" ]] || { usage >&2; exit 1; }
  validate_probe "$probe" || { echo "Command denied" >&2; exit 1; }
  validate_profile "$profile" || { echo "Invalid profile" >&2; exit 1; }
  [[ "$lines" =~ ^[0-9]+$ ]] || { echo "Invalid lines" >&2; exit 1; }
  if (( lines < 1 || lines > MAX_LINES )); then
    echo "Invalid lines" >&2
    exit 1
  fi
  if [[ "$probe" != "runtime_log_tail_v2" && "$lines" != "$DEFAULT_LINES" ]]; then
    echo "--lines is only supported for runtime_log_tail_v2" >&2
    exit 1
  fi

  local start_ms end_ms duration_ms payload output_bytes tmp_output rc
  start_ms="$(monotonic_ms)"
  tmp_output="$(mktemp)"
  rc=0

  if ! payload="$(read_snapshot_payload "$probe" "$profile" "$lines")"; then
    rc=$?
    payload="$(emit_degraded_json "$profile" "$probe" '{"helper_error":true}')"
  fi

  printf '%s\n' "$payload" > "$tmp_output"
  output_bytes="$(wc -c < "$tmp_output" | tr -d ' ')"
  if (( output_bytes > MAX_OUTPUT_BYTES )); then
    payload="$(emit_degraded_json "$profile" "$probe" "$(jq -cn --argjson output_bytes "$output_bytes" --argjson limit "$MAX_OUTPUT_BYTES" '{output_truncated:true,output_bytes:$output_bytes,output_limit_bytes:$limit}')")"
    printf '%s\n' "$payload" > "$tmp_output"
    output_bytes="$(wc -c < "$tmp_output" | tr -d ' ')"
  fi

  cat "$tmp_output"
  end_ms="$(monotonic_ms)"
  duration_ms="$(( end_ms - start_ms ))"
  log_event "dispatch" "$profile" "$probe" "$rc" "$duration_ms" "$output_bytes" "ok"
  rm -f "$tmp_output"
}

main "$@"
