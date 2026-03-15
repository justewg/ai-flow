#!/usr/bin/env bash
set -euo pipefail

readonly PUBLIC_ROOT="/etc/ai-flow/public"
readonly PROJECT_PUBLIC_ROOT="${PUBLIC_ROOT}/projects"
readonly DIAGNOSTICS_ROOT="/var/lib/ai-flow/diagnostics"
readonly DEFAULT_INTERVAL_SEC="15"
readonly MAX_SNAPSHOT_BYTES="262144"
readonly MAX_LOG_LINES="200"
readonly CURL_TIMEOUT_SEC="4"

usage() {
  cat <<'EOF'
Usage:
  remote_agent_v2_publisher.sh --profile <profile>

Publish sanitized diagnostics snapshots for Remote Agent v2.
EOF
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
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

project_public_env_for_profile() {
  printf '%s/%s.env' "$PROJECT_PUBLIC_ROOT" "$1"
}

publisher_interval_for_profile() {
  local env_file="$1"
  local value
  value="$(read_env_key "$env_file" "AI_FLOW_DIAGNOSTICS_PUBLISH_INTERVAL_SEC" || true)"
  if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 )); then
    printf '%s' "$value"
  else
    printf '%s' "$DEFAULT_INTERVAL_SEC"
  fi
}

diagnostics_dir_for_profile() {
  local env_file="$1"
  local profile="$2"
  local value
  value="$(read_env_key "$env_file" "AI_FLOW_DIAGNOSTICS_DIR" || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s/%s' "$DIAGNOSTICS_ROOT" "$profile"
  fi
}

file_exists_json() {
  [[ -e "$1" ]] && printf 'true' || printf 'false'
}

capture_http_json() {
  local url="$1"
  curl -fsS --max-time "$CURL_TIMEOUT_SEC" "$url"
}

capture_http_status() {
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code}' --max-time "$CURL_TIMEOUT_SEC" "$url" 2>/dev/null || true
}

tail_lines_json() {
  local file_path="$1"
  local lines="$2"
  if [[ -f "$file_path" ]]; then
    tail -n "$lines" "$file_path" | redact_sensitive_text | jq -Rsc 'split("\n") | map(select(length > 0))'
  else
    printf '[]'
  fi
}

redact_sensitive_text() {
  sed -E \
    -e 's/(Bearer )[A-Za-z0-9._=-]+/\1[REDACTED]/g' \
    -e 's/(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]+/[REDACTED_GH_TOKEN]/g' \
    -e 's/github_pat_[A-Za-z0-9_]+/[REDACTED_GH_TOKEN]/g' \
    -e 's/sk-[A-Za-z0-9_-]+/[REDACTED_OPENAI_TOKEN]/g' \
    -e 's/(OPENAI_API_KEY|DAEMON_GH_PROJECT_TOKEN|GH_APP_INTERNAL_SECRET|OPS_BOT_DEBUG_BEARER_TOKEN|OPS_REMOTE_STATUS_PUSH_SECRET|OPS_REMOTE_SUMMARY_PUSH_SECRET|OPS_BOT_TG_SECRET_TOKEN|OPS_BOT_WEBHOOK_SECRET|OPS_BOT_TG_BOT_TOKEN|DAEMON_TG_BOT_TOKEN)=([^[:space:]]+)/\1=[REDACTED]/g'
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

lines_to_json_array() {
  printf '%s' "${1:-}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

write_snapshot() {
  local target_path="$1"
  local payload="$2"
  local size staging_dir tmp_file

  staging_dir="$(dirname "$target_path")/.staging"
  mkdir -p "$staging_dir"
  chmod 0700 "$staging_dir"
  tmp_file="$(mktemp "${staging_dir}/snapshot.XXXXXX")"
  printf '%s\n' "$payload" > "$tmp_file"
  size="$(wc -c < "$tmp_file" | tr -d ' ')"
  if (( size > MAX_SNAPSHOT_BYTES )); then
    rm -f "$tmp_file"
    echo "Snapshot exceeds max size: ${target_path}" >&2
    exit 1
  fi
  chmod 0640 "$tmp_file"
  mv -f "$tmp_file" "$target_path"
}

emit_runtime_snapshot() {
  local profile="$1"
  local project_env="$2"
  local interval="$3"
  local ttl="$4"
  local ops_bind ops_port health_url status_url health_http status_http health_json status_json
  ops_bind="$(read_env_key "$project_env" "OPS_BOT_BIND" || true)"
  ops_port="$(read_env_key "$project_env" "OPS_BOT_PORT" || true)"
  [[ -n "$ops_bind" ]] || ops_bind="127.0.0.1"
  [[ -n "$ops_port" ]] || ops_port="8790"

  health_url="http://${ops_bind}:${ops_port}/health"
  status_url="http://${ops_bind}:${ops_port}/ops/status.json"
  health_http="$(capture_http_status "$health_url")"
  status_http="$(capture_http_status "$status_url")"
  health_json='{}'
  status_json='{}'
  if [[ "$health_http" == "200" ]]; then
    health_json="$(capture_http_json "$health_url")"
  fi
  if [[ "$status_http" == "200" ]]; then
    status_json="$(capture_http_json "$status_url")"
  fi

  jq -cn \
    --arg profile "$profile" \
    --arg published_at "$(now_utc)" \
    --argjson publisher_interval_sec "$interval" \
    --argjson snapshot_ttl_sec "$ttl" \
    --arg health_url "$health_url" \
    --arg status_url "$status_url" \
    --arg health_http_status "$health_http" \
    --arg status_http_status "$status_http" \
    --argjson health "$health_json" \
    --argjson status "$status_json" \
    '{
      schema_version: 1,
      profile: $profile,
      published_at: $published_at,
      publisher_interval_sec: $publisher_interval_sec,
      snapshot_ttl_sec: $snapshot_ttl_sec,
      source: {
        health_url: $health_url,
        status_url: $status_url,
        health_http_status: $health_http_status,
        status_http_status: $status_http_status
      },
      health: $health,
      status: $status
    }'
}

emit_runtime_log_tail() {
  local profile="$1"
  local project_env="$2"
  local interval="$3"
  local ttl="$4"
  local runtime_log_dir
  runtime_log_dir="$(read_env_key "$project_env" "FLOW_RUNTIME_LOG_DIR" || true)"
  jq -cn \
    --arg profile "$profile" \
    --arg published_at "$(now_utc)" \
    --arg runtime_log_dir "$runtime_log_dir" \
    --argjson publisher_interval_sec "$interval" \
    --argjson snapshot_ttl_sec "$ttl" \
    --argjson daemon "$(tail_lines_json "${runtime_log_dir}/daemon.log" "$MAX_LOG_LINES")" \
    --argjson watchdog "$(tail_lines_json "${runtime_log_dir}/watchdog.log" "$MAX_LOG_LINES")" \
    --argjson executor "$(tail_lines_json "${runtime_log_dir}/executor.log" "$MAX_LOG_LINES")" \
    --argjson graphql_rate "$(tail_lines_json "${runtime_log_dir}/graphql_rate_stats.log" "$MAX_LOG_LINES")" \
    '{
      schema_version: 1,
      profile: $profile,
      published_at: $published_at,
      publisher_interval_sec: $publisher_interval_sec,
      snapshot_ttl_sec: $snapshot_ttl_sec,
      runtime_log_dir: $runtime_log_dir,
      logs: {
        daemon: $daemon,
        watchdog: $watchdog,
        executor: $executor,
        "graphql-rate": $graphql_rate
      }
    }'
}

emit_compose_metadata() {
  local profile="$1"
  local project_env="$2"
  local interval="$3"
  local ttl="$4"
  local compose_root compose_file compose_env_file services whole_home_mount platform_env_wired
  compose_root="$(read_env_key "$project_env" "COMPOSE_ROOT" || true)"
  compose_file="$(read_env_key "$project_env" "COMPOSE_FILE" || true)"
  compose_env_file="$(read_env_key "$project_env" "COMPOSE_ENV_FILE" || true)"
  services="$(list_compose_services "$compose_file")"
  whole_home_mount="0"
  platform_env_wired="0"
  if [[ -f "$compose_file" ]] && grep -Eq '^[[:space:]]*-[[:space:]]*/home/[^:]+:/home/[^[:space:]]+' "$compose_file"; then
    whole_home_mount="1"
  fi
  if [[ -f "$compose_file" ]] && grep -Eq 'PLATFORM_ENV_FILE|/etc/ai-flow/public/platform\.env' "$compose_file"; then
    platform_env_wired="1"
  fi

  jq -cn \
    --arg profile "$profile" \
    --arg published_at "$(now_utc)" \
    --arg compose_root "$compose_root" \
    --arg compose_file "$compose_file" \
    --arg compose_env_file "$compose_env_file" \
    --argjson publisher_interval_sec "$interval" \
    --argjson snapshot_ttl_sec "$ttl" \
    --argjson compose_root_exists "$(file_exists_json "$compose_root")" \
    --argjson compose_file_exists "$(file_exists_json "$compose_file")" \
    --argjson compose_env_file_exists "$(file_exists_json "$compose_env_file")" \
    --argjson platform_env_wired "$([[ "$platform_env_wired" == "1" ]] && echo true || echo false)" \
    --argjson whole_home_mount_present "$([[ "$whole_home_mount" == "1" ]] && echo true || echo false)" \
    --argjson services "$(lines_to_json_array "$services")" \
    '{
      schema_version: 1,
      profile: $profile,
      published_at: $published_at,
      publisher_interval_sec: $publisher_interval_sec,
      snapshot_ttl_sec: $snapshot_ttl_sec,
      compose_root: $compose_root,
      compose_root_exists: $compose_root_exists,
      compose_file: $compose_file,
      compose_file_exists: $compose_file_exists,
      compose_env_file: $compose_env_file,
      compose_env_file_exists: $compose_env_file_exists,
      platform_env_wired: $platform_env_wired,
      whole_home_mount_present: $whole_home_mount_present,
      services: $services
    }'
}

emit_ingress_metadata() {
  local profile="$1"
  local project_env="$2"
  local platform_env="${PUBLIC_ROOT}/platform.env"
  local interval="$3"
  local ttl="$4"
  local public_base_url conf_file host_name health_present status_present debug_present webhook_present
  public_base_url="$(read_env_key "$platform_env" "OPS_BOT_PUBLIC_BASE_URL" || true)"
  conf_file="$(read_env_key "$project_env" "NGINX_CONF_FILE" || true)"
  host_name="$(printf '%s' "$public_base_url" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:.*$##')"
  [[ -n "$conf_file" ]] || conf_file="/etc/nginx/conf.d/${host_name}.conf"
  health_present="0"
  status_present="0"
  debug_present="0"
  webhook_present="0"
  if [[ -f "$conf_file" ]]; then
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/health([[:space:]]|\{)' "$conf_file" && health_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/status(\.json)?([[:space:]]|\{)' "$conf_file" && status_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/ops/debug/([[:space:]]|\{)' "$conf_file" && debug_present="1" || true
    grep -Eq 'location[[:space:]]*(=|~\*|~)?[[:space:]]*/telegram/webhook(/|[[:space:]]|\{)' "$conf_file" && webhook_present="1" || true
  fi

  jq -cn \
    --arg profile "$profile" \
    --arg published_at "$(now_utc)" \
    --arg public_base_url "$public_base_url" \
    --arg host_name "$host_name" \
    --arg conf_file "$conf_file" \
    --argjson publisher_interval_sec "$interval" \
    --argjson snapshot_ttl_sec "$ttl" \
    --argjson conf_exists "$(file_exists_json "$conf_file")" \
    --argjson health_present "$([[ "$health_present" == "1" ]] && echo true || echo false)" \
    --argjson status_present "$([[ "$status_present" == "1" ]] && echo true || echo false)" \
    --argjson debug_present "$([[ "$debug_present" == "1" ]] && echo true || echo false)" \
    --argjson webhook_present "$([[ "$webhook_present" == "1" ]] && echo true || echo false)" \
    '{
      schema_version: 1,
      profile: $profile,
      published_at: $published_at,
      publisher_interval_sec: $publisher_interval_sec,
      snapshot_ttl_sec: $snapshot_ttl_sec,
      public_base_url: $public_base_url,
      host_name: $host_name,
      conf_file: $conf_file,
      conf_exists: $conf_exists,
      locations: {
        health: $health_present,
        ops_status: $status_present,
        ops_debug: $debug_present,
        telegram_webhook: $webhook_present
      },
      diagnostics_exposed_externally: ($status_present or $debug_present or $health_present)
    }'
}

emit_workspace_metadata() {
  local profile="$1"
  local project_env="$2"
  local interval="$3"
  local ttl="$4"
  local workspace_path branch shared_head root_dirty_count shared_dirty_count flow_env_symlink
  workspace_path="$(read_env_key "$project_env" "WORKSPACE_PATH" || true)"
  branch=""
  shared_head=""
  root_dirty_count="0"
  shared_dirty_count="0"
  flow_env_symlink="false"
  if [[ -d "$workspace_path/.git" || -f "$workspace_path/.git" ]]; then
    branch="$(git -C "$workspace_path" branch --show-current 2>/dev/null || true)"
    root_dirty_count="$(git -C "$workspace_path" status --short 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [[ -d "$workspace_path/.flow/shared/.git" || -f "$workspace_path/.flow/shared/.git" ]]; then
    shared_head="$(git -C "$workspace_path/.flow/shared" rev-parse --short HEAD 2>/dev/null || true)"
    shared_dirty_count="$(git -C "$workspace_path/.flow/shared" status --short 2>/dev/null | wc -l | tr -d ' ')"
  fi
  [[ -L "$workspace_path/.flow/config/flow.env" ]] && flow_env_symlink="true"

  jq -cn \
    --arg profile "$profile" \
    --arg published_at "$(now_utc)" \
    --arg workspace_path "$workspace_path" \
    --arg branch "$branch" \
    --arg shared_head "$shared_head" \
    --argjson publisher_interval_sec "$interval" \
    --argjson snapshot_ttl_sec "$ttl" \
    --argjson workspace_exists "$(file_exists_json "$workspace_path")" \
    --argjson root_dirty_count "${root_dirty_count:-0}" \
    --argjson shared_dirty_count "${shared_dirty_count:-0}" \
    --argjson flow_env_symlink "$flow_env_symlink" \
    '{
      schema_version: 1,
      profile: $profile,
      published_at: $published_at,
      publisher_interval_sec: $publisher_interval_sec,
      snapshot_ttl_sec: $snapshot_ttl_sec,
      workspace_path: $workspace_path,
      workspace_exists: $workspace_exists,
      current_branch: $branch,
      root_dirty_count: $root_dirty_count,
      shared_head: $shared_head,
      shared_dirty_count: $shared_dirty_count,
      flow_env_symlink: $flow_env_symlink
    }'
}

main() {
  local profile=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      --profile)
        [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
        profile="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ "$(id -u)" -eq 0 ]] || {
    echo "This publisher must run as root." >&2
    exit 1
  }

  [[ -n "$profile" ]] || { echo "--profile is required" >&2; exit 1; }
  [[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Invalid profile" >&2; exit 1; }

  local project_env interval ttl diagnostics_dir
  project_env="$(project_public_env_for_profile "$profile")"
  [[ -f "$project_env" ]] || { echo "Missing public project env: ${project_env}" >&2; exit 1; }
  interval="$(publisher_interval_for_profile "$project_env")"
  ttl="$(( interval * 2 ))"
  diagnostics_dir="$(diagnostics_dir_for_profile "$project_env" "$profile")"

  mkdir -p "$diagnostics_dir"
  chmod 0750 "$diagnostics_dir"

  write_snapshot "${diagnostics_dir}/runtime_snapshot.json" "$(emit_runtime_snapshot "$profile" "$project_env" "$interval" "$ttl")"
  write_snapshot "${diagnostics_dir}/runtime_log_tail.json" "$(emit_runtime_log_tail "$profile" "$project_env" "$interval" "$ttl")"
  write_snapshot "${diagnostics_dir}/compose_metadata.json" "$(emit_compose_metadata "$profile" "$project_env" "$interval" "$ttl")"
  write_snapshot "${diagnostics_dir}/ingress_metadata.json" "$(emit_ingress_metadata "$profile" "$project_env" "$interval" "$ttl")"
  write_snapshot "${diagnostics_dir}/workspace_metadata.json" "$(emit_workspace_metadata "$profile" "$project_env" "$interval" "$ttl")"
}

main "$@"
