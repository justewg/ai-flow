#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

PROFILE_NAME="$(codex_resolve_project_profile_name)"
AI_FLOW_ROOT_DIR="$(codex_resolve_ai_flow_root_dir)"
PROJECT_ENV_FILE="$(codex_resolve_flow_env_file)"
PLATFORM_ENV_FILE="${AI_FLOW_PLATFORM_ENV_FILE:-${AI_FLOW_ROOT_DIR}/config/ai-flow.platform.env}"
RUNTIME_LOG_DIR="$(codex_resolve_flow_runtime_log_dir)"
CODEX_STATE_DIR="$(codex_resolve_state_dir)"
COMPOSE_ROOT="${AI_FLOW_ROOT_DIR}/docker/${PROFILE_NAME}"
COMPOSE_ENV_FILE="${COMPOSE_ROOT}/.env"
COMPOSE_FILE="${COMPOSE_ROOT}/docker-compose.yml"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/remote_probe.sh <subcommand> [options]

Read-only probe kit for SSH-assisted diagnostics. Only fixed allowlisted probes are supported.

Subcommands:
  semantically_overqualified_runtime_snapshot_env_audit_bundle_v1
  semantically_overqualified_runtime_log_tail_bundle_v1 [--lines N]
  semantically_overqualified_docker_compose_contract_surface_v1
  semantically_overqualified_ops_bot_debug_gate_surface_v1
  semantically_overqualified_nginx_ingress_surface_v1
  semantically_overqualified_workspace_git_surface_v1

Notes:
  - no arbitrary file paths
  - no arbitrary shell commands
  - outputs JSON only
EOF
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required" >&2
    exit 1
  }
}

read_env_key() {
  local env_file="$1"
  local key="$2"
  codex_read_key_from_env_file "$env_file" "$key" || true
}

bool_json() {
  if [[ "${1:-0}" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

lines_to_json_array() {
  local input="${1:-}"
  printf '%s' "$input" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

tail_file_or_empty() {
  local file_path="$1"
  local lines="$2"
  if [[ -f "$file_path" ]]; then
    tail -n "$lines" "$file_path"
  fi
}

file_exists_json() {
  [[ -e "$1" ]] && printf 'true' || printf 'false'
}

capture_http_status() {
  local url="$1"
  shift || true
  curl -sS -o /dev/null -w '%{http_code}' "$@" "$url" 2>/dev/null || true
}

list_compose_services() {
  local compose_file="$1"
  [[ -f "$compose_file" ]] || return 0
  awk '
    BEGIN { in_services=0 }
    /^services:[[:space:]]*$/ { in_services=1; next }
    in_services && /^[^[:space:]]/ { exit }
    in_services && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ {
      line=$0
      sub(/^  /, "", line)
      sub(/:[[:space:]]*$/, "", line)
      print line
    }
  ' "$compose_file"
}

emit_runtime_snapshot_env_audit_bundle() {
  local snapshot_json env_audit_output env_ready env_summary
  snapshot_json="$("${CODEX_SHARED_SCRIPTS_DIR}/status_snapshot.sh")"
  env_audit_output="$("${CODEX_SHARED_SCRIPTS_DIR}/env_audit.sh" --profile "$PROFILE_NAME" 2>&1 || true)"
  env_ready="$(printf '%s\n' "$env_audit_output" | sed -n 's/^ENV_AUDIT_READY=//p' | tail -n1)"
  env_summary="$(printf '%s\n' "$env_audit_output" | sed -n 's/^SUMMARY //p' | tail -n1)"

  jq -n \
    --arg profile "$PROFILE_NAME" \
    --arg ai_flow_root_dir "$AI_FLOW_ROOT_DIR" \
    --arg project_env_file "$PROJECT_ENV_FILE" \
    --arg platform_env_file "$PLATFORM_ENV_FILE" \
    --arg runtime_log_dir "$RUNTIME_LOG_DIR" \
    --arg codex_state_dir "$CODEX_STATE_DIR" \
    --arg env_audit_output "$env_audit_output" \
    --arg env_audit_summary "$env_summary" \
    --argjson snapshot "$snapshot_json" \
    --argjson env_audit_ready "$(bool_json "${env_ready:-0}")" \
    '{
      probe: "semantically_overqualified_runtime_snapshot_env_audit_bundle_v1",
      profile: $profile,
      paths: {
        ai_flow_root_dir: $ai_flow_root_dir,
        project_env_file: $project_env_file,
        platform_env_file: $platform_env_file,
        runtime_log_dir: $runtime_log_dir,
        codex_state_dir: $codex_state_dir
      },
      snapshot: $snapshot,
      env_audit: {
        ready: $env_audit_ready,
        summary: $env_audit_summary,
        output: $env_audit_output
      }
    }'
}

emit_runtime_log_tail_bundle() {
  local lines="120"
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
  [[ "$lines" =~ ^[0-9]+$ ]] || { echo "--lines must be integer" >&2; exit 1; }
  if (( lines < 1 || lines > 400 )); then
    echo "--lines must be within 1..400" >&2
    exit 1
  fi

  local daemon_text watchdog_text executor_text graphql_text
  daemon_text="$(tail_file_or_empty "${RUNTIME_LOG_DIR}/daemon.log" "$lines")"
  watchdog_text="$(tail_file_or_empty "${RUNTIME_LOG_DIR}/watchdog.log" "$lines")"
  executor_text="$(tail_file_or_empty "${RUNTIME_LOG_DIR}/executor.log" "$lines")"
  graphql_text="$(tail_file_or_empty "${RUNTIME_LOG_DIR}/graphql_rate_stats.log" "$lines")"

  jq -n \
    --argjson lines "$lines" \
    --arg daemon_text "$daemon_text" \
    --arg watchdog_text "$watchdog_text" \
    --arg executor_text "$executor_text" \
    --arg graphql_text "$graphql_text" \
    '{
      probe: "semantically_overqualified_runtime_log_tail_bundle_v1",
      lines: $lines,
      logs: {
        daemon: $daemon_text,
        watchdog: $watchdog_text,
        executor: $executor_text,
        "graphql-rate": $graphql_text
      }
    }'
}

emit_docker_compose_contract_surface() {
  local services_output mount_excerpt runtime_home_pattern platform_env_from_compose_env
  local platform_env_wired="0" whole_home_mount_present="0"
  services_output="$(list_compose_services "$COMPOSE_FILE")"
  runtime_home_pattern="$(read_env_key "$COMPOSE_ENV_FILE" "RUNTIME_HOME")"
  [[ -n "$runtime_home_pattern" ]] || runtime_home_pattern="/home/unknown"
  platform_env_from_compose_env="$(read_env_key "$COMPOSE_ENV_FILE" "PLATFORM_ENV_FILE")"

  if [[ -f "$COMPOSE_FILE" ]] && grep -Eq '^[[:space:]]*-[[:space:]]*\$\{PLATFORM_ENV_FILE\}' "$COMPOSE_FILE"; then
    platform_env_wired="1"
  fi
  if [[ -f "$COMPOSE_FILE" ]] && grep -Fq "${runtime_home_pattern}:${runtime_home_pattern}" "$COMPOSE_FILE"; then
    whole_home_mount_present="1"
  fi

  mount_excerpt="$(
    if [[ -f "$COMPOSE_FILE" ]]; then
      rg -n -C 1 '/var/sites/\.ai-flow|/home/' "$COMPOSE_FILE" || true
    fi
  )"

  jq -n \
    --arg compose_root "$COMPOSE_ROOT" \
    --arg compose_env_file "$COMPOSE_ENV_FILE" \
    --arg compose_file "$COMPOSE_FILE" \
    --arg platform_env_file "$PLATFORM_ENV_FILE" \
    --arg platform_env_file_from_compose_env "$platform_env_from_compose_env" \
    --arg project_env_file "$PROJECT_ENV_FILE" \
    --arg openai_env_file "$(read_env_key "$COMPOSE_ENV_FILE" "OPENAI_ENV_FILE")" \
    --arg runtime_home "$runtime_home_pattern" \
    --arg resolved_mount_excerpt "$mount_excerpt" \
    --argjson compose_root_exists "$(file_exists_json "$COMPOSE_ROOT")" \
    --argjson compose_env_exists "$(file_exists_json "$COMPOSE_ENV_FILE")" \
    --argjson compose_file_exists "$(file_exists_json "$COMPOSE_FILE")" \
    --argjson platform_env_wired "$(bool_json "$platform_env_wired")" \
    --argjson whole_home_mount_present "$(bool_json "$whole_home_mount_present")" \
    --argjson services "$(lines_to_json_array "$services_output")" \
    '{
      probe: "semantically_overqualified_docker_compose_contract_surface_v1",
      compose_root: $compose_root,
      compose_root_exists: $compose_root_exists,
      compose_env_file: $compose_env_file,
      compose_env_exists: $compose_env_exists,
      compose_file: $compose_file,
      compose_file_exists: $compose_file_exists,
      platform_env_file: $platform_env_file,
      platform_env_file_from_compose_env: $platform_env_file_from_compose_env,
      project_env_file: $project_env_file,
      openai_env_file: $openai_env_file,
      runtime_home: $runtime_home,
      platform_env_wired: $platform_env_wired,
      whole_home_mount_present: $whole_home_mount_present,
      services: $services,
      resolved_mount_excerpt: $resolved_mount_excerpt
    }'
}

emit_ops_bot_debug_gate_surface() {
  local ops_port debug_enabled debug_token
  local health_http_status debug_http_status debug_enabled_normalized
  ops_port="$(read_env_key "$PROJECT_ENV_FILE" "OPS_BOT_PORT")"
  [[ -n "$ops_port" ]] || ops_port="8790"
  debug_enabled="$(read_env_key "$PLATFORM_ENV_FILE" "OPS_BOT_DEBUG_ENABLED")"
  debug_enabled_normalized="$(printf '%s' "$debug_enabled" | tr '[:upper:]' '[:lower:]')"
  debug_token="$(read_env_key "$PLATFORM_ENV_FILE" "OPS_BOT_DEBUG_BEARER_TOKEN")"
  health_http_status="$(capture_http_status "http://127.0.0.1:${ops_port}/health")"
  debug_http_status=""
  if [[ -n "$debug_token" ]]; then
    debug_http_status="$(capture_http_status "http://127.0.0.1:${ops_port}/ops/debug/runtime.json" -H "Authorization: Bearer ${debug_token}")"
  fi

  jq -n \
    --arg ops_port "$ops_port" \
    --arg debug_enabled_raw "$debug_enabled" \
    --arg health_http_status "$health_http_status" \
    --arg debug_http_status "$debug_http_status" \
    --arg platform_env_file "$PLATFORM_ENV_FILE" \
    --arg compose_env_file "$COMPOSE_ENV_FILE" \
    --arg compose_file "$COMPOSE_FILE" \
    --argjson debug_token_present "$(bool_json "$([[ -n "$debug_token" ]] && echo 1 || echo 0)")" \
    --argjson debug_enabled_truthy "$(bool_json "$([[ "$debug_enabled_normalized" =~ ^(1|true|yes|on)$ ]] && echo 1 || echo 0)")" \
    --argjson platform_env_file_exists "$(file_exists_json "$PLATFORM_ENV_FILE")" \
    --argjson compose_env_file_exists "$(file_exists_json "$COMPOSE_ENV_FILE")" \
    --argjson compose_file_exists "$(file_exists_json "$COMPOSE_FILE")" \
    '{
      probe: "semantically_overqualified_ops_bot_debug_gate_surface_v1",
      ops_port: $ops_port,
      debug_enabled_raw: $debug_enabled_raw,
      debug_enabled_truthy: $debug_enabled_truthy,
      debug_token_present: $debug_token_present,
      health_http_status: $health_http_status,
      debug_http_status: $debug_http_status,
      platform_env_file: $platform_env_file,
      platform_env_file_exists: $platform_env_file_exists,
      compose_env_file: $compose_env_file,
      compose_env_file_exists: $compose_env_file_exists,
      compose_file: $compose_file,
      compose_file_exists: $compose_file_exists
    }'
}

emit_nginx_ingress_surface() {
  local public_base_url host_name conf_file excerpt
  local health_present="0" ops_present="0" debug_present="0" webhook_present="0"
  public_base_url="$(read_env_key "$PLATFORM_ENV_FILE" "OPS_BOT_PUBLIC_BASE_URL")"
  host_name="$(printf '%s' "$public_base_url" | sed -E 's#^[a-z]+://##; s#/.*$##; s/:.*$##')"
  conf_file="/etc/nginx/conf.d/${host_name}.conf"
  if [[ -f "$conf_file" ]]; then
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/health([[:space:]]|\{)' "$conf_file" && health_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/([[:space:]]|\{)' "$conf_file" && ops_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/debug/([[:space:]]|\{)' "$conf_file" && debug_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/telegram/webhook(/|[[:space:]]|\{)' "$conf_file" && webhook_present="1" || true
  fi
  excerpt="$(rg -n -C 2 'location = /health|location /ops/debug/|location /ops/|location /telegram/webhook' "$conf_file" 2>/dev/null || true)"

  jq -n \
    --arg public_base_url "$public_base_url" \
    --arg host_name "$host_name" \
    --arg conf_file "$conf_file" \
    --arg excerpt "$excerpt" \
    --argjson conf_exists "$(file_exists_json "$conf_file")" \
    --argjson health_present "$(bool_json "$health_present")" \
    --argjson ops_present "$(bool_json "$ops_present")" \
    --argjson debug_present "$(bool_json "$debug_present")" \
    --argjson webhook_present "$(bool_json "$webhook_present")" \
    '{
      probe: "semantically_overqualified_nginx_ingress_surface_v1",
      public_base_url: $public_base_url,
      host_name: $host_name,
      conf_file: $conf_file,
      conf_exists: $conf_exists,
      locations: {
        health: $health_present,
        ops: $ops_present,
        ops_debug: $debug_present,
        telegram_webhook: $webhook_present
      },
      excerpt: $excerpt
    }'
}

emit_workspace_git_surface() {
  local git_status shared_status submodule_status current_branch shared_head
  git_status="$(git status --short)"
  current_branch="$(git branch --show-current)"
  shared_status="$(git -C .flow/shared status --short 2>/dev/null || true)"
  shared_head="$(git -C .flow/shared rev-parse --short HEAD 2>/dev/null || true)"
  submodule_status="$(git submodule status .flow/shared 2>/dev/null || true)"

  jq -n \
    --arg current_branch "$current_branch" \
    --arg shared_head "$shared_head" \
    --arg submodule_status "$submodule_status" \
    --argjson git_status_lines "$(lines_to_json_array "$git_status")" \
    --argjson shared_status_lines "$(lines_to_json_array "$shared_status")" \
    '{
      probe: "semantically_overqualified_workspace_git_surface_v1",
      current_branch: $current_branch,
      git_status_lines: $git_status_lines,
      shared_head: $shared_head,
      shared_status_lines: $shared_status_lines,
      submodule_status: $submodule_status
    }'
}

require_jq

subcommand="${1:-}"
shift || true

case "$subcommand" in
  semantically_overqualified_runtime_snapshot_env_audit_bundle_v1)
    emit_runtime_snapshot_env_audit_bundle
    ;;
  semantically_overqualified_runtime_log_tail_bundle_v1)
    emit_runtime_log_tail_bundle "$@"
    ;;
  semantically_overqualified_docker_compose_contract_surface_v1)
    emit_docker_compose_contract_surface
    ;;
  semantically_overqualified_ops_bot_debug_gate_surface_v1)
    emit_ops_bot_debug_gate_surface
    ;;
  semantically_overqualified_nginx_ingress_surface_v1)
    emit_nginx_ingress_surface
    ;;
  semantically_overqualified_workspace_git_surface_v1)
    emit_workspace_git_surface
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown subcommand: ${subcommand}" >&2
    usage >&2
    exit 1
    ;;
esac
