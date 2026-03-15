#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

profile=""
platform_env_file=""
project_env_file=""

ok_count=0
warn_count=0
fail_count=0
action_count=0

platform_core_required=(
  "AI_FLOW_ROOT_DIR"
  "FLOW_HOST_RUNTIME_MODE"
)

platform_full_expected=(
  "OPS_BOT_PUBLIC_BASE_URL"
  "GH_APP_PM2_APP_NAME"
  "OPS_BOT_PM2_APP_NAME"
)

platform_optional=(
  "OPS_BOT_DEBUG_ENABLED"
  "OPS_BOT_DEBUG_BEARER_TOKEN"
  "OPS_BOT_DEBUG_DEFAULT_LINES"
  "OPS_BOT_DEBUG_MAX_LINES"
  "OPS_BOT_DEBUG_MAX_BYTES"
)

project_core_required=(
  "PROJECT_PROFILE"
  "GITHUB_REPO"
  "FLOW_BASE_BRANCH"
  "FLOW_HEAD_BRANCH"
  "PROJECT_OWNER"
  "PROJECT_NUMBER"
  "PROJECT_ID"
  "DAEMON_GH_PROJECT_TOKEN"
  "GH_APP_INTERNAL_SECRET"
  "GH_APP_ID"
  "GH_APP_INSTALLATION_ID"
  "GH_APP_PRIVATE_KEY_PATH"
  "AI_FLOW_ROOT_DIR"
  "CODEX_STATE_DIR"
  "FLOW_STATE_DIR"
  "FLOW_LOGS_DIR"
  "FLOW_RUNTIME_LOG_DIR"
  "FLOW_PM2_LOG_DIR"
  "FLOW_HOST_RUNTIME_MODE"
  "GH_APP_BIND"
  "GH_APP_PORT"
  "GH_APP_TOKEN_SKEW_SEC"
  "DAEMON_GH_AUTH_TIMEOUT_SEC"
  "OPS_BOT_BIND"
  "OPS_BOT_PORT"
  "OPS_BOT_WEBHOOK_PATH"
  "OPS_BOT_REMOTE_STATE_DIR"
  "OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC"
  "OPS_BOT_REMOTE_SUMMARY_TTL_SEC"
)

project_full_expected=(
  "GH_APP_OWNER"
  "GH_APP_REPO"
  "GH_APP_PM2_USE_DEFAULT"
  "OPS_BOT_USE_DEFAULT"
  "OPS_BOT_REFRESH_SEC"
  "OPS_BOT_CMD_TIMEOUT_MS"
  "FLOW_LAUNCHD_NAMESPACE"
  "WATCHDOG_DAEMON_LABEL"
  "WATCHDOG_DAEMON_INTERVAL_SEC"
)

project_optional=(
  "EXECUTOR_CODEX_BYPASS_SANDBOX"
  "DAEMON_GH_AUTH_TOKEN_URL"
  "DAEMON_GH_TOKEN_FALLBACK_ENABLED"
  "DAEMON_GH_TOKEN"
  "DAEMON_TG_BOT_TOKEN"
  "DAEMON_TG_CHAT_ID"
  "DAEMON_TG_REMINDER_SEC"
  "DAEMON_TG_GH_DNS_REMINDER_SEC"
  "DAEMON_TG_DIRTY_REMINDER_SEC"
  "DEPENDENCY_ISSUE_RESOLVED_CACHE_TTL_SEC"
  "WATCHDOG_COOLDOWN_SEC"
  "WATCHDOG_EXECUTOR_STALE_SEC"
  "WATCHDOG_DAEMON_LOG_STALE_SEC"
  "WATCHDOG_DAEMON_LOG_STALE_RATE_LIMIT_SEC"
  "OPS_BOT_TG_BOT_TOKEN"
  "OPS_BOT_WEBHOOK_SECRET"
  "OPS_BOT_TG_SECRET_TOKEN"
  "OPS_BOT_ALLOWED_CHAT_IDS"
)

platform_only_keys=(
  "OPS_BOT_PUBLIC_BASE_URL"
  "OPS_BOT_DEBUG_ENABLED"
  "OPS_BOT_DEBUG_BEARER_TOKEN"
  "OPS_BOT_DEBUG_DEFAULT_LINES"
  "OPS_BOT_DEBUG_MAX_LINES"
  "OPS_BOT_DEBUG_MAX_BYTES"
  "GH_APP_PM2_APP_NAME"
  "OPS_BOT_PM2_APP_NAME"
)

project_only_keys=(
  "PROJECT_PROFILE"
  "GITHUB_REPO"
  "FLOW_BASE_BRANCH"
  "FLOW_HEAD_BRANCH"
  "PROJECT_OWNER"
  "PROJECT_NUMBER"
  "PROJECT_ID"
  "DAEMON_GH_PROJECT_TOKEN"
  "GH_APP_INTERNAL_SECRET"
  "GH_APP_ID"
  "GH_APP_INSTALLATION_ID"
  "GH_APP_PRIVATE_KEY_PATH"
  "GH_APP_OWNER"
  "GH_APP_REPO"
  "GH_APP_BIND"
  "GH_APP_PORT"
  "GH_APP_TOKEN_SKEW_SEC"
  "GH_APP_PM2_USE_DEFAULT"
  "DAEMON_GH_AUTH_TIMEOUT_SEC"
  "DAEMON_GH_AUTH_TOKEN_URL"
  "DAEMON_GH_TOKEN_FALLBACK_ENABLED"
  "DAEMON_GH_TOKEN"
  "DAEMON_TG_BOT_TOKEN"
  "DAEMON_TG_CHAT_ID"
  "DAEMON_TG_REMINDER_SEC"
  "DAEMON_TG_GH_DNS_REMINDER_SEC"
  "DAEMON_TG_DIRTY_REMINDER_SEC"
  "FLOW_LAUNCHD_NAMESPACE"
  "WATCHDOG_DAEMON_LABEL"
  "WATCHDOG_DAEMON_INTERVAL_SEC"
  "WATCHDOG_COOLDOWN_SEC"
  "WATCHDOG_EXECUTOR_STALE_SEC"
  "WATCHDOG_DAEMON_LOG_STALE_SEC"
  "WATCHDOG_DAEMON_LOG_STALE_RATE_LIMIT_SEC"
  "CODEX_STATE_DIR"
  "FLOW_STATE_DIR"
  "FLOW_LOGS_DIR"
  "FLOW_RUNTIME_LOG_DIR"
  "FLOW_PM2_LOG_DIR"
  "OPS_BOT_USE_DEFAULT"
  "OPS_BOT_BIND"
  "OPS_BOT_PORT"
  "OPS_BOT_WEBHOOK_PATH"
  "OPS_BOT_WEBHOOK_SECRET"
  "OPS_BOT_TG_SECRET_TOKEN"
  "OPS_BOT_ALLOWED_CHAT_IDS"
  "OPS_BOT_REFRESH_SEC"
  "OPS_BOT_CMD_TIMEOUT_MS"
  "OPS_BOT_TG_BOT_TOKEN"
  "OPS_BOT_REMOTE_STATE_DIR"
  "OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC"
  "OPS_BOT_REMOTE_SUMMARY_TTL_SEC"
)

project_optional_prefixes=(
  "OPS_REMOTE_STATUS_PUSH_"
  "OPS_REMOTE_SUMMARY_PUSH_"
)

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/env_audit.sh [options]

Options:
  --profile <name>             Audit project env for the given profile in addition to platform env.
  --platform-env-file <path>   Explicit ai-flow platform env path.
  --project-env-file <path>    Explicit project env path.
  -h, --help                   Show help.

Examples:
  .flow/shared/scripts/env_audit.sh
  .flow/shared/scripts/env_audit.sh --profile planka
  .flow/shared/scripts/env_audit.sh --profile planka --project-env-file /var/sites/.ai-flow/config/planka.flow.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --platform-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform-env-file" >&2; exit 1; }
      platform_env_file="$2"
      shift 2
      ;;
    --project-env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --project-env-file" >&2; exit 1; }
      project_env_file="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

report_ok() {
  ok_count=$((ok_count + 1))
  printf '✅ CHECK_OK %s=%s\n' "$1" "$2"
}

report_warn() {
  warn_count=$((warn_count + 1))
  printf '⚠️ CHECK_WARN %s=%s\n' "$1" "$2"
}

report_fail() {
  fail_count=$((fail_count + 1))
  printf '❌ CHECK_FAIL %s=%s\n' "$1" "$2"
}

report_action() {
  action_count=$((action_count + 1))
  printf '👉 ACTION %s=%s\n' "$1" "$2"
}

section() {
  printf '\n## %s\n' "$1"
}

join_by() {
  local delimiter="$1"
  shift || true
  local first="1"
  local item
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    if [[ "$first" == "1" ]]; then
      printf '%s' "$item"
      first="0"
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
}

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

key_matches_prefixes() {
  local key="$1"
  shift || true
  local prefix
  for prefix in "$@"; do
    [[ "$key" == "${prefix}"* ]] && return 0
  done
  return 1
}

read_env_keys_into_array() {
  local file_path="$1"
  local array_name="$2"
  local line key
  eval "$array_name=()"
  [[ -f "$file_path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -n "${line//[[:space:]]/}" ]] || continue
    key="$(printf '%s' "$line" | sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p')"
    [[ -n "$key" ]] || continue
    eval "$array_name+=(\"$key\")"
  done < "$file_path"
}

env_value() {
  local env_file="$1"
  local key="$2"
  codex_read_key_from_env_file "$env_file" "$key" || true
}

detect_platform_env_file() {
  local ai_flow_root_dir candidate
  if [[ -n "$platform_env_file" ]]; then
    printf '%s' "$platform_env_file"
    return 0
  fi
  if [[ -n "${AI_FLOW_PLATFORM_ENV_FILE:-}" ]]; then
    printf '%s' "$AI_FLOW_PLATFORM_ENV_FILE"
    return 0
  fi
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  candidate="${ai_flow_root_dir}/config/ai-flow.platform.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="${HOME}/.config/ai-flow/ai-flow.platform.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  printf '%s' "${ai_flow_root_dir}/config/ai-flow.platform.env"
}

detect_project_env_file() {
  local profile_slug="$1"
  local ai_flow_root_dir candidate
  if [[ -n "$project_env_file" ]]; then
    printf '%s' "$project_env_file"
    return 0
  fi
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" && -f "${DAEMON_GH_ENV_FILE}" ]]; then
    printf '%s' "${DAEMON_GH_ENV_FILE}"
    return 0
  fi
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  candidate="${ai_flow_root_dir}/config/${profile_slug}.flow.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(codex_resolve_flow_env_file)"
  printf '%s' "$candidate"
}

report_missing_keys() {
  local env_file="$1"
  local label_prefix="$2"
  local severity="$3"
  shift 3 || true
  local key value
  for key in "$@"; do
    value="$(env_value "$env_file" "$key")"
    if [[ -n "$value" ]]; then
      report_ok "${label_prefix}_${key}" "present"
    else
      if [[ "$severity" == "fail" ]]; then
        report_fail "${label_prefix}_${key}" "missing"
        report_action "${label_prefix}_${key}" "Добавь ${key} в ${env_file}"
      else
        report_warn "${label_prefix}_${key}" "missing"
        report_action "${label_prefix}_${key}" "Если следуешь полному стандартному contract, добавь ${key} в ${env_file}"
      fi
    fi
  done
}

check_legacy_value() {
  local key="$1"
  local value="$2"
  if [[ "$value" == *"/private/"* || "$value" == *"~/Library"* || "$value" == *"LaunchAgents"* || "$value" == *"planka-automation"* ]]; then
    return 0
  fi
  if [[ "$key" == "OPS_BOT_REMOTE_STATE_DIR" ]]; then
    [[ "$value" == ".flow/state/ops-bot/remote" || "$value" == *"/.flow/state/ops-bot/remote" ]] && return 0
  fi
  if [[ "$key" == "GH_APP_PM2_APP_NAME" || "$key" == "OPS_BOT_PM2_APP_NAME" ]]; then
    [[ "$value" == planka-* ]] && return 0
  fi
  return 1
}

check_platform_file() {
  local env_file="$1"
  local env_keys=()
  local key value bad_keys=() misplaced_keys=() legacy_keys=()
  section "Platform Env"
  if [[ -f "$env_file" ]]; then
    report_ok "PLATFORM_ENV_FILE" "$env_file"
  else
    report_fail "PLATFORM_ENV_FILE" "missing:${env_file}"
    report_action "PLATFORM_ENV_FILE" "Создай host-level platform env: ${env_file}"
    return 0
  fi

  read_env_keys_into_array "$env_file" env_keys
  report_missing_keys "$env_file" "PLATFORM_CORE" "fail" "${platform_core_required[@]}"
  report_missing_keys "$env_file" "PLATFORM_STANDARD" "warn" "${platform_full_expected[@]}"

  for key in "${env_keys[@]}"; do
    value="$(env_value "$env_file" "$key")"
    if array_contains "$key" "${project_only_keys[@]}"; then
      misplaced_keys+=("$key")
      continue
    fi
    if array_contains "$key" "${platform_core_required[@]}" || array_contains "$key" "${platform_full_expected[@]}" || array_contains "$key" "${platform_optional[@]}"; then
      :
    else
      bad_keys+=("$key")
    fi
    if check_legacy_value "$key" "$value"; then
      legacy_keys+=("${key}=${value}")
    fi
  done

  if [[ "${#misplaced_keys[@]}" -gt 0 ]]; then
    report_warn "PLATFORM_MISPLACED_KEYS" "$(join_by "," "${misplaced_keys[@]}")"
    report_action "PLATFORM_MISPLACED_KEYS" "Перенеси project-specific ключи из ${env_file} в <profile>.flow.env"
  else
    report_ok "PLATFORM_MISPLACED_KEYS" "none"
  fi

  if [[ "${#bad_keys[@]}" -gt 0 ]]; then
    report_warn "PLATFORM_UNEXPECTED_KEYS" "$(join_by "," "${bad_keys[@]}")"
    report_action "PLATFORM_UNEXPECTED_KEYS" "Удали или задокументируй неожиданные host-level ключи в ${env_file}"
  else
    report_ok "PLATFORM_UNEXPECTED_KEYS" "none"
  fi

  if [[ "${#legacy_keys[@]}" -gt 0 ]]; then
    report_warn "PLATFORM_LEGACY_VALUES" "$(join_by ";" "${legacy_keys[@]}")"
    report_action "PLATFORM_LEGACY_VALUES" "Убери legacy/macOS/project-specific значения из ${env_file}"
  else
    report_ok "PLATFORM_LEGACY_VALUES" "none"
  fi
}

check_project_file() {
  local env_file="$1"
  local project_profile="$2"
  local env_keys=()
  local key value bad_keys=() misplaced_keys=() legacy_keys=()
  local project_ai_flow_root platform_ai_flow_root expected_logs_dir expected_runtime_dir expected_pm2_dir expected_state_dir expected_remote_state_dir project_profile_value

  section "Project Env"
  if [[ -f "$env_file" ]]; then
    report_ok "PROJECT_ENV_FILE" "$env_file"
  else
    report_fail "PROJECT_ENV_FILE" "missing:${env_file}"
    report_action "PROJECT_ENV_FILE" "Создай project env для профиля ${project_profile}: ${env_file}"
    return 0
  fi

  read_env_keys_into_array "$env_file" env_keys
  report_missing_keys "$env_file" "PROJECT_CORE" "fail" "${project_core_required[@]}"
  report_missing_keys "$env_file" "PROJECT_STANDARD" "warn" "${project_full_expected[@]}"

  for key in "${env_keys[@]}"; do
    value="$(env_value "$env_file" "$key")"
    if array_contains "$key" "${platform_only_keys[@]}"; then
      misplaced_keys+=("$key")
      continue
    fi
    if array_contains "$key" "${project_core_required[@]}" || array_contains "$key" "${project_full_expected[@]}" || array_contains "$key" "${project_optional[@]}" || key_matches_prefixes "$key" "${project_optional_prefixes[@]}"; then
      :
    else
      bad_keys+=("$key")
    fi
    if check_legacy_value "$key" "$value"; then
      legacy_keys+=("${key}=${value}")
    fi
  done

  if [[ "${#misplaced_keys[@]}" -gt 0 ]]; then
    report_warn "PROJECT_MISPLACED_KEYS" "$(join_by "," "${misplaced_keys[@]}")"
    report_action "PROJECT_MISPLACED_KEYS" "Перенеси host/platform ключи из ${env_file} в ai-flow.platform.env"
  else
    report_ok "PROJECT_MISPLACED_KEYS" "none"
  fi

  if [[ "${#bad_keys[@]}" -gt 0 ]]; then
    report_warn "PROJECT_UNEXPECTED_KEYS" "$(join_by "," "${bad_keys[@]}")"
    report_action "PROJECT_UNEXPECTED_KEYS" "Удали или задокументируй неожиданные project-level ключи в ${env_file}"
  else
    report_ok "PROJECT_UNEXPECTED_KEYS" "none"
  fi

  if [[ "${#legacy_keys[@]}" -gt 0 ]]; then
    report_warn "PROJECT_LEGACY_VALUES" "$(join_by ";" "${legacy_keys[@]}")"
    report_action "PROJECT_LEGACY_VALUES" "Убери legacy/macOS/old-layout значения из ${env_file}"
  else
    report_ok "PROJECT_LEGACY_VALUES" "none"
  fi

  project_profile_value="$(env_value "$env_file" "PROJECT_PROFILE")"
  if [[ -n "$project_profile_value" && "$project_profile_value" != "$project_profile" ]]; then
    report_fail "PROJECT_PROFILE_MATCH" "expected:${project_profile};actual:${project_profile_value}"
    report_action "PROJECT_PROFILE_MATCH" "Синхронизируй PROJECT_PROFILE с --profile ${project_profile}"
  else
    report_ok "PROJECT_PROFILE_MATCH" "$project_profile"
  fi

  project_ai_flow_root="$(env_value "$env_file" "AI_FLOW_ROOT_DIR")"
  platform_ai_flow_root="$(env_value "$platform_env_file" "AI_FLOW_ROOT_DIR")"
  if [[ -n "$project_ai_flow_root" && -n "$platform_ai_flow_root" && "$project_ai_flow_root" != "$platform_ai_flow_root" ]]; then
    report_fail "AI_FLOW_ROOT_DIR_MATCH" "platform:${platform_ai_flow_root};project:${project_ai_flow_root}"
    report_action "AI_FLOW_ROOT_DIR_MATCH" "Сделай один host root в ai-flow.platform.env и ${env_file}"
  elif [[ -n "$project_ai_flow_root" ]]; then
    report_ok "AI_FLOW_ROOT_DIR_MATCH" "$project_ai_flow_root"
  fi

  if [[ -n "$project_ai_flow_root" ]]; then
    expected_state_dir="${project_ai_flow_root}/state/${project_profile}"
    expected_logs_dir="${project_ai_flow_root}/logs/${project_profile}"
    expected_runtime_dir="${expected_logs_dir}/runtime"
    expected_pm2_dir="${expected_logs_dir}/pm2"
    expected_remote_state_dir="${project_ai_flow_root}/state/ops-bot/remote"

    [[ "$(env_value "$env_file" "CODEX_STATE_DIR")" == "$expected_state_dir" ]] \
      && report_ok "CODEX_STATE_DIR_LAYOUT" "$expected_state_dir" \
      || { report_warn "CODEX_STATE_DIR_LAYOUT" "expected:${expected_state_dir};actual:$(env_value "$env_file" "CODEX_STATE_DIR")"; report_action "CODEX_STATE_DIR_LAYOUT" "Выстави CODEX_STATE_DIR=${expected_state_dir}"; }

    [[ "$(env_value "$env_file" "FLOW_STATE_DIR")" == "$expected_state_dir" ]] \
      && report_ok "FLOW_STATE_DIR_LAYOUT" "$expected_state_dir" \
      || { report_warn "FLOW_STATE_DIR_LAYOUT" "expected:${expected_state_dir};actual:$(env_value "$env_file" "FLOW_STATE_DIR")"; report_action "FLOW_STATE_DIR_LAYOUT" "Выстави FLOW_STATE_DIR=${expected_state_dir}"; }

    [[ "$(env_value "$env_file" "FLOW_LOGS_DIR")" == "$expected_logs_dir" ]] \
      && report_ok "FLOW_LOGS_DIR_LAYOUT" "$expected_logs_dir" \
      || { report_warn "FLOW_LOGS_DIR_LAYOUT" "expected:${expected_logs_dir};actual:$(env_value "$env_file" "FLOW_LOGS_DIR")"; report_action "FLOW_LOGS_DIR_LAYOUT" "Выстави FLOW_LOGS_DIR=${expected_logs_dir}"; }

    [[ "$(env_value "$env_file" "FLOW_RUNTIME_LOG_DIR")" == "$expected_runtime_dir" ]] \
      && report_ok "FLOW_RUNTIME_LOG_DIR_LAYOUT" "$expected_runtime_dir" \
      || { report_warn "FLOW_RUNTIME_LOG_DIR_LAYOUT" "expected:${expected_runtime_dir};actual:$(env_value "$env_file" "FLOW_RUNTIME_LOG_DIR")"; report_action "FLOW_RUNTIME_LOG_DIR_LAYOUT" "Выстави FLOW_RUNTIME_LOG_DIR=${expected_runtime_dir}"; }

    [[ "$(env_value "$env_file" "FLOW_PM2_LOG_DIR")" == "$expected_pm2_dir" ]] \
      && report_ok "FLOW_PM2_LOG_DIR_LAYOUT" "$expected_pm2_dir" \
      || { report_warn "FLOW_PM2_LOG_DIR_LAYOUT" "expected:${expected_pm2_dir};actual:$(env_value "$env_file" "FLOW_PM2_LOG_DIR")"; report_action "FLOW_PM2_LOG_DIR_LAYOUT" "Выстави FLOW_PM2_LOG_DIR=${expected_pm2_dir}"; }

    [[ "$(env_value "$env_file" "OPS_BOT_REMOTE_STATE_DIR")" == "$expected_remote_state_dir" ]] \
      && report_ok "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "$expected_remote_state_dir" \
      || { report_warn "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "expected:${expected_remote_state_dir};actual:$(env_value "$env_file" "OPS_BOT_REMOTE_STATE_DIR")"; report_action "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "Выстави OPS_BOT_REMOTE_STATE_DIR=${expected_remote_state_dir}"; }
  fi
}

platform_env_file="$(detect_platform_env_file)"

section "Env Audit"
report_ok "ROOT_DIR" "$ROOT_DIR"
report_ok "AI_FLOW_ROOT_DIR" "$(codex_resolve_ai_flow_root_dir)"

check_platform_file "$platform_env_file"

if [[ -n "$profile" ]]; then
  profile="$(slugify "$profile")"
  project_env_file="$(detect_project_env_file "$profile")"
  check_project_file "$project_env_file" "$profile"
else
  section "Project Env"
  report_warn "PROJECT_ENV_SKIPPED" "profile-not-specified"
  report_action "PROJECT_ENV_SKIPPED" "Для project env аудита запусти: .flow/shared/scripts/run.sh env_audit --profile <name>"
fi

printf '\nSUMMARY ok=%s warn=%s fail=%s action=%s\n' "$ok_count" "$warn_count" "$fail_count" "$action_count"
printf 'ENV_AUDIT_READY=%s\n' "$([[ "$fail_count" -eq 0 ]] && printf '%s' 1 || printf '%s' 0)"
