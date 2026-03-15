#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

profile=""
platform_env_file=""
project_env_file=""
fix_mode="0"

ok_count=0
warn_count=0
fail_count=0
action_count=0

platform_missing_core_keys=()
platform_missing_standard_keys=()
platform_disable_keys=()
platform_malformed_lines=()
project_missing_core_keys=()
project_missing_standard_keys=()
project_disable_keys=()
project_malformed_lines=()

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
  --fix                        Comment out misplaced/legacy keys and append grouped placeholders for missing keys.
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
    --fix)
      fix_mode="1"
      shift
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

array_append_unique() {
  local array_name="$1"
  local value="$2"
  [[ -n "$value" ]] || return 0
  local item
  local array_items=()
  eval "array_items=(\"\${${array_name}[@]-}\")"
  for item in "${array_items[@]}"; do
    [[ "$item" == "$value" ]] && return 0
  done
  eval "${array_name}+=(\"\$value\")"
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

collect_malformed_env_lines() {
  local file_path="$1"
  local array_name="$2"
  local line line_no=0
  eval "$array_name=()"
  [[ -f "$file_path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -n "${line//[[:space:]]/}" ]] || continue
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*= ]]; then
      continue
    fi
    eval "${array_name}+=(\"${line_no}:${line}\")"
  done < "$file_path"
}

env_value() {
  local env_file="$1"
  local key="$2"
  codex_read_key_from_env_file "$env_file" "$key" || true
}

canonicalize_file_path() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    local dir_path base_name
    dir_path="$(cd "$(dirname "$file_path")" && pwd -P)"
    base_name="$(basename "$file_path")"
    printf '%s/%s' "$dir_path" "$base_name"
  else
    printf '%s' "$file_path"
  fi
}

env_file_has_key() {
  local env_file="$1"
  local key="$2"
  [[ -f "$env_file" ]] || return 1
  grep -Eq "^[[:space:]]*#?[[:space:]]*(env_audit disabled:[[:space:]]*)?(export[[:space:]]+)?${key}=" "$env_file"
}

key_fix_hint() {
  local scope="$1"
  local key="$2"
  case "$key" in
    AI_FLOW_ROOT_DIR)
      printf '%s' "host-level ai-flow root, обычно /var/sites/.ai-flow"
      ;;
    FLOW_HOST_RUNTIME_MODE)
      printf '%s' "режим текущего хоста, для VPS docker contour обычно linux-docker-hosted"
      ;;
    OPS_BOT_PUBLIC_BASE_URL)
      printf '%s' "внешний ingress URL host-level ops-bot, например https://aiflow.ewg40.ru"
      ;;
    OPS_BOT_DEBUG_BEARER_TOKEN)
      printf '%s' "длинный bearer token для /ops/debug/*"
      ;;
    OPS_BOT_DEBUG_ENABLED)
      printf '%s' "1 если debug API должен быть включён"
      ;;
    GH_APP_PM2_APP_NAME)
      printf '%s' "host-level PM2 app name; platform default ai-flow-gh-app-auth"
      ;;
    OPS_BOT_PM2_APP_NAME)
      printf '%s' "host-level PM2 app name; platform default ai-flow-ops-bot"
      ;;
    PROJECT_PROFILE)
      printf '%s' "slug consumer-project, например planka"
      ;;
    GITHUB_REPO)
      printf '%s' "owner/repo из git origin или GitHub URL"
      ;;
    FLOW_BASE_BRANCH)
      printf '%s' "обычно main"
      ;;
    FLOW_HEAD_BRANCH)
      printf '%s' "обычно development"
      ;;
    PROJECT_OWNER)
      printf '%s' "owner Project v2 из GitHub URL"
      ;;
    PROJECT_NUMBER)
      printf '%s' "номер Project v2 из GitHub URL"
      ;;
    PROJECT_ID)
      printf '%s' "gh project view <number> --owner <owner> --format json --jq '.id'"
      ;;
    DAEMON_GH_PROJECT_TOKEN)
      printf '%s' "PAT для project/runtime access"
      ;;
    GH_APP_INTERNAL_SECRET)
      printf '%s' "shared secret между daemon/watchdog и auth-service"
      ;;
    GH_APP_ID)
      printf '%s' "GitHub App settings -> App ID"
      ;;
    GH_APP_INSTALLATION_ID)
      printf '%s' "installation id GitHub App"
      ;;
    GH_APP_PRIVATE_KEY_PATH)
      printf '%s' "локальный путь к .pem GitHub App key"
      ;;
    GH_APP_OWNER)
      printf '%s' "owner GitHub App installation, обычно repo owner"
      ;;
    GH_APP_REPO)
      printf '%s' "repo name GitHub App installation"
      ;;
    GH_APP_BIND)
      printf '%s' "локальный bind auth-service, обычно 127.0.0.1"
      ;;
    GH_APP_PORT)
      printf '%s' "локальный порт auth-service, обычно 8787"
      ;;
    GH_APP_TOKEN_SKEW_SEC)
      printf '%s' "запас refresh токена, обычно 300"
      ;;
    DAEMON_GH_AUTH_TIMEOUT_SEC)
      printf '%s' "таймаут запроса к auth-service, обычно 8"
      ;;
    CODEX_STATE_DIR|FLOW_STATE_DIR)
      printf '%s' "обычно <AI_FLOW_ROOT_DIR>/state/<PROJECT_PROFILE>"
      ;;
    FLOW_LOGS_DIR)
      printf '%s' "обычно <AI_FLOW_ROOT_DIR>/logs/<PROJECT_PROFILE>"
      ;;
    FLOW_RUNTIME_LOG_DIR)
      printf '%s' "обычно <AI_FLOW_ROOT_DIR>/logs/<PROJECT_PROFILE>/runtime"
      ;;
    FLOW_PM2_LOG_DIR)
      printf '%s' "обычно <AI_FLOW_ROOT_DIR>/logs/<PROJECT_PROFILE>/pm2"
      ;;
    OPS_BOT_BIND)
      printf '%s' "локальный bind ops-bot, обычно 127.0.0.1"
      ;;
    OPS_BOT_PORT)
      printf '%s' "локальный порт ops-bot, обычно 8790"
      ;;
    OPS_BOT_WEBHOOK_PATH)
      printf '%s' "локальный webhook path, обычно /telegram/webhook"
      ;;
    OPS_BOT_REMOTE_STATE_DIR)
      printf '%s' "обычно <AI_FLOW_ROOT_DIR>/state/ops-bot/remote"
      ;;
    OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC)
      printf '%s' "TTL remote snapshot, обычно 600"
      ;;
    OPS_BOT_REMOTE_SUMMARY_TTL_SEC)
      printf '%s' "TTL remote summary, обычно 1200"
      ;;
    FLOW_LAUNCHD_NAMESPACE)
      printf '%s' "обычно com.flow"
      ;;
    WATCHDOG_DAEMON_LABEL)
      printf '%s' "label daemon, обычно derived из namespace+profile"
      ;;
    WATCHDOG_DAEMON_INTERVAL_SEC)
      printf '%s' "обычно 45"
      ;;
    *)
      if [[ "$scope" == "platform" ]]; then
        printf '%s' "добавь host/platform значение по текущему deployment contract"
      else
        printf '%s' "добавь project/runtime значение по текущему deployment contract"
      fi
      ;;
  esac
}

ensure_env_file_for_fix() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$env_file")"
  : > "$env_file"
}

disable_keys_in_env_file() {
  local env_file="$1"
  local array_name="$2"
  local tmp_file line key
  local keys_ref=()
  eval "keys_ref=(\"\${${array_name}[@]-}\")"
  [[ "${#keys_ref[@]}" -gt 0 ]] || return 0
  tmp_file="$(mktemp "${env_file}.env_audit.XXXXXX")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[2]}"
      if array_contains "$key" "${keys_ref[@]}"; then
        printf '# env_audit disabled: %s\n' "$line" >> "$tmp_file"
        continue
      fi
    fi
    printf '%s\n' "$line" >> "$tmp_file"
  done < "$env_file"
  mv "$tmp_file" "$env_file"
}

disable_malformed_lines_in_env_file() {
  local env_file="$1"
  local array_name="$2"
  local tmp_file line line_no=0 entry malformed_line
  local malformed_ref=()
  eval "malformed_ref=(\"\${${array_name}[@]-}\")"
  [[ "${#malformed_ref[@]}" -gt 0 ]] || return 0
  tmp_file="$(mktemp "${env_file}.env_audit.XXXXXX")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    malformed_line=""
    for entry in "${malformed_ref[@]}"; do
      [[ "$entry" == "${line_no}:"* ]] || continue
      malformed_line="${entry#*:}"
      break
    done
    if [[ -n "$malformed_line" ]]; then
      printf '# env_audit disabled malformed: %s\n' "$line" >> "$tmp_file"
      continue
    fi
    printf '%s\n' "$line" >> "$tmp_file"
  done < "$env_file"
  mv "$tmp_file" "$env_file"
}

append_missing_group() {
  local env_file="$1"
  local scope="$2"
  local title="$3"
  local array_name="$4"
  local key added_any="0"
  local keys_ref=()
  eval "keys_ref=(\"\${${array_name}[@]-}\")"
  [[ "${#keys_ref[@]}" -gt 0 ]] || return 0
  for key in "${keys_ref[@]}"; do
    [[ -n "$key" ]] || continue
    if env_file_has_key "$env_file" "$key"; then
      continue
    fi
    if [[ "$added_any" == "0" ]]; then
      printf '\n# env_audit fix: %s\n' "$title" >> "$env_file"
      added_any="1"
    fi
    printf '# add %s: %s\n' "$key" "$(key_fix_hint "$scope" "$key")" >> "$env_file"
    printf '%s=\n' "$key" >> "$env_file"
  done
}

repair_workspace_env_symlink() {
  local workspace_env_file="$1"
  local host_env_file="$2"
  local backup_path=""

  mkdir -p "$(dirname "$workspace_env_file")"
  mkdir -p "$(dirname "$host_env_file")"
  [[ -f "$host_env_file" ]] || : > "$host_env_file"

  if [[ -L "$workspace_env_file" ]]; then
    ln -sfn "$host_env_file" "$workspace_env_file"
    return 0
  fi

  if [[ -f "$workspace_env_file" ]]; then
    backup_path="${workspace_env_file}.pre-symlink-backup.$(date +%s)"
    cp "$workspace_env_file" "$backup_path"
    rm -f "$workspace_env_file"
    report_ok "FLOW_ENV_WORKSPACE_BACKUP" "$backup_path"
  else
    rm -f "$workspace_env_file"
  fi

  ln -s "$host_env_file" "$workspace_env_file"
}

apply_fix_to_env_file() {
  local env_file="$1"
  local scope="$2"
  local disable_array_name="$3"
  local malformed_array_name="$4"
  local missing_core_array_name="$5"
  local missing_standard_array_name="$6"
  local disable_ref=()
  local filtered_disable_ref=()
  local malformed_ref=()
  local filtered_malformed_ref=()
  local key
  local scope_label
  eval "disable_ref=(\"\${${disable_array_name}[@]-}\")"
  eval "malformed_ref=(\"\${${malformed_array_name}[@]-}\")"
  for key in "${disable_ref[@]}"; do
    [[ -n "$key" ]] || continue
    filtered_disable_ref+=("$key")
  done
  for key in "${malformed_ref[@]}"; do
    [[ -n "$key" ]] || continue
    filtered_malformed_ref+=("$key")
  done
  scope_label="$(printf '%s' "$scope" | tr '[:lower:]' '[:upper:]')"
  ensure_env_file_for_fix "$env_file"
  disable_malformed_lines_in_env_file "$env_file" "$malformed_array_name"
  disable_keys_in_env_file "$env_file" "$disable_array_name"
  append_missing_group "$env_file" "$scope" "${scope} missing core keys" "$missing_core_array_name"
  append_missing_group "$env_file" "$scope" "${scope} missing standard keys" "$missing_standard_array_name"
  if [[ "${#filtered_malformed_ref[@]}" -gt 0 ]]; then
    report_ok "${scope_label}_FIX_DISABLED_MALFORMED" "$(join_by ";" "${filtered_malformed_ref[@]}")"
  fi
  if [[ "${#filtered_disable_ref[@]}" -gt 0 ]]; then
    report_ok "${scope_label}_FIX_DISABLED_KEYS" "$(join_by "," "${filtered_disable_ref[@]}")"
  fi
  report_ok "${scope_label}_FIX_APPLIED" "$env_file"
}

detect_platform_env_file() {
  local ai_flow_root_dir candidate
  if [[ -n "$platform_env_file" ]]; then
    printf '%s' "$(canonicalize_file_path "$platform_env_file")"
    return 0
  fi
  if [[ -n "${AI_FLOW_PLATFORM_ENV_FILE:-}" ]]; then
    printf '%s' "$(canonicalize_file_path "$AI_FLOW_PLATFORM_ENV_FILE")"
    return 0
  fi
  ai_flow_root_dir="$(detect_ai_flow_root_dir)"
  candidate="${ai_flow_root_dir}/config/ai-flow.platform.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$(canonicalize_file_path "$candidate")"
    return 0
  fi
  candidate="${HOME}/.config/ai-flow/ai-flow.platform.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$(canonicalize_file_path "$candidate")"
    return 0
  fi
  printf '%s' "${ai_flow_root_dir}/config/ai-flow.platform.env"
}

detect_ai_flow_root_dir() {
  local candidate env_root
  if [[ -n "${AI_FLOW_ROOT_DIR:-}" ]]; then
    printf '%s' "${AI_FLOW_ROOT_DIR}"
    return 0
  fi
  if [[ -n "${AI_FLOW_PLATFORM_ENV_FILE:-}" && -f "${AI_FLOW_PLATFORM_ENV_FILE}" ]]; then
    env_root="$(env_value "${AI_FLOW_PLATFORM_ENV_FILE}" "AI_FLOW_ROOT_DIR")"
    if [[ -n "$env_root" ]]; then
      printf '%s' "$env_root"
      return 0
    fi
  fi
  if [[ -n "$platform_env_file" && -f "$platform_env_file" ]]; then
    env_root="$(env_value "$platform_env_file" "AI_FLOW_ROOT_DIR")"
    if [[ -n "$env_root" ]]; then
      printf '%s' "$env_root"
      return 0
    fi
  fi
  if [[ -n "$project_env_file" && -f "$project_env_file" ]]; then
    env_root="$(env_value "$project_env_file" "AI_FLOW_ROOT_DIR")"
    if [[ -n "$env_root" ]]; then
      printf '%s' "$env_root"
      return 0
    fi
  fi
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" && -f "${DAEMON_GH_ENV_FILE}" ]]; then
    env_root="$(env_value "${DAEMON_GH_ENV_FILE}" "AI_FLOW_ROOT_DIR")"
    if [[ -n "$env_root" ]]; then
      printf '%s' "$env_root"
      return 0
    fi
  fi
  if [[ -n "$profile" ]]; then
    candidate="$(detect_project_env_file "$(slugify "$profile")")"
    if [[ -f "$candidate" ]]; then
      env_root="$(env_value "$candidate" "AI_FLOW_ROOT_DIR")"
      if [[ -n "$env_root" ]]; then
        printf '%s' "$env_root"
        return 0
      fi
    fi
  fi
  codex_resolve_ai_flow_root_dir
}

detect_project_env_file() {
  local profile_slug="$1"
  local ai_flow_root_dir candidate
  if [[ -n "$project_env_file" ]]; then
    printf '%s' "$(canonicalize_file_path "$project_env_file")"
    return 0
  fi
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" && -f "${DAEMON_GH_ENV_FILE}" ]]; then
    printf '%s' "$(canonicalize_file_path "${DAEMON_GH_ENV_FILE}")"
    return 0
  fi
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  candidate="${ai_flow_root_dir}/config/${profile_slug}.flow.env"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$(canonicalize_file_path "$candidate")"
    return 0
  fi
  candidate="$(codex_resolve_flow_env_file)"
  printf '%s' "$(canonicalize_file_path "$candidate")"
}

report_missing_keys() {
  local env_file="$1"
  local label_prefix="$2"
  local severity="$3"
  local collect_array_name="$4"
  shift 4 || true
  local key value
  for key in "$@"; do
    value="$(env_value "$env_file" "$key")"
    if [[ -n "$value" ]]; then
      report_ok "${label_prefix}_${key}" "present"
    else
      if [[ -n "$collect_array_name" && "$collect_array_name" != "-" ]]; then
        array_append_unique "$collect_array_name" "$key"
      fi
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
    if [[ "$fix_mode" == "1" ]]; then
      ensure_env_file_for_fix "$env_file"
      report_ok "PLATFORM_ENV_FILE_FIX" "created:${env_file}"
    else
      return 0
    fi
  fi

  read_env_keys_into_array "$env_file" env_keys
  collect_malformed_env_lines "$env_file" platform_malformed_lines
  report_missing_keys "$env_file" "PLATFORM_CORE" "fail" "platform_missing_core_keys" "${platform_core_required[@]}"
  report_missing_keys "$env_file" "PLATFORM_STANDARD" "warn" "platform_missing_standard_keys" "${platform_full_expected[@]}"

  if [[ "${#platform_malformed_lines[@]}" -gt 0 ]]; then
    report_fail "PLATFORM_MALFORMED_LINES" "$(join_by ";" "${platform_malformed_lines[@]}")"
    report_action "PLATFORM_MALFORMED_LINES" "Удали или закомментируй некорректные строки в ${env_file}"
  else
    report_ok "PLATFORM_MALFORMED_LINES" "none"
  fi

  for key in "${env_keys[@]}"; do
    value="$(env_value "$env_file" "$key")"
    if array_contains "$key" "${project_only_keys[@]}"; then
      misplaced_keys+=("$key")
      array_append_unique "platform_disable_keys" "$key"
      continue
    fi
    if array_contains "$key" "${platform_core_required[@]}" || array_contains "$key" "${platform_full_expected[@]}" || array_contains "$key" "${platform_optional[@]}"; then
      :
    else
      bad_keys+=("$key")
      array_append_unique "platform_disable_keys" "$key"
    fi
    if check_legacy_value "$key" "$value"; then
      legacy_keys+=("${key}=${value}")
      array_append_unique "platform_disable_keys" "$key"
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

  if [[ "$fix_mode" == "1" ]]; then
    apply_fix_to_env_file "$env_file" "platform" "platform_disable_keys" "platform_malformed_lines" "platform_missing_core_keys" "platform_missing_standard_keys"
  fi
}

check_project_file() {
  local env_file="$1"
  local project_profile="$2"
  local env_keys=()
  local key value bad_keys=() misplaced_keys=() legacy_keys=()
  local flow_env_needs_repair="0"
  local project_ai_flow_root platform_ai_flow_root expected_logs_dir expected_runtime_dir expected_pm2_dir expected_state_dir expected_remote_state_dir project_profile_value
  local expected_host_env_file workspace_env_file workspace_env_target

  section "Project Env"
  if [[ -f "$env_file" ]]; then
    report_ok "PROJECT_ENV_FILE" "$env_file"
  else
    report_fail "PROJECT_ENV_FILE" "missing:${env_file}"
    report_action "PROJECT_ENV_FILE" "Создай project env для профиля ${project_profile}: ${env_file}"
    if [[ "$fix_mode" == "1" ]]; then
      ensure_env_file_for_fix "$env_file"
      report_ok "PROJECT_ENV_FILE_FIX" "created:${env_file}"
    else
      return 0
    fi
  fi

  read_env_keys_into_array "$env_file" env_keys
  collect_malformed_env_lines "$env_file" project_malformed_lines
  report_missing_keys "$env_file" "PROJECT_CORE" "fail" "project_missing_core_keys" "${project_core_required[@]}"
  report_missing_keys "$env_file" "PROJECT_STANDARD" "warn" "project_missing_standard_keys" "${project_full_expected[@]}"

  if [[ "${#project_malformed_lines[@]}" -gt 0 ]]; then
    report_fail "PROJECT_MALFORMED_LINES" "$(join_by ";" "${project_malformed_lines[@]}")"
    report_action "PROJECT_MALFORMED_LINES" "Удали или закомментируй некорректные строки в ${env_file}"
  else
    report_ok "PROJECT_MALFORMED_LINES" "none"
  fi

  for key in "${env_keys[@]}"; do
    value="$(env_value "$env_file" "$key")"
    if array_contains "$key" "${platform_only_keys[@]}"; then
      misplaced_keys+=("$key")
      array_append_unique "project_disable_keys" "$key"
      continue
    fi
    if array_contains "$key" "${project_core_required[@]}" || array_contains "$key" "${project_full_expected[@]}" || array_contains "$key" "${project_optional[@]}" || key_matches_prefixes "$key" "${project_optional_prefixes[@]}"; then
      :
    else
      bad_keys+=("$key")
      array_append_unique "project_disable_keys" "$key"
    fi
    if check_legacy_value "$key" "$value"; then
      legacy_keys+=("${key}=${value}")
      array_append_unique "project_disable_keys" "$key"
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
    expected_host_env_file="${project_ai_flow_root}/config/${project_profile}.flow.env"
    workspace_env_file="${ROOT_DIR}/.flow/config/flow.env"
    expected_state_dir="${project_ai_flow_root}/state/${project_profile}"
    expected_logs_dir="${project_ai_flow_root}/logs/${project_profile}"
    expected_runtime_dir="${expected_logs_dir}/runtime"
    expected_pm2_dir="${expected_logs_dir}/pm2"
    expected_remote_state_dir="${project_ai_flow_root}/state/ops-bot/remote"

    if [[ -L "$workspace_env_file" ]]; then
      workspace_env_target="$(readlink "$workspace_env_file")"
      if [[ "$workspace_env_target" != /* ]]; then
        workspace_env_target="$(cd "$(dirname "$workspace_env_file")/$(dirname "$workspace_env_target")" && pwd -P)/$(basename "$workspace_env_target")"
      fi
      if [[ "$workspace_env_target" == "$expected_host_env_file" ]]; then
        report_ok "FLOW_ENV_SYMLINK" "${workspace_env_file} -> ${expected_host_env_file}"
      else
        flow_env_needs_repair="1"
        report_warn "FLOW_ENV_SYMLINK" "unexpected-target:${workspace_env_target}"
        report_action "FLOW_ENV_SYMLINK" "Сделай ${workspace_env_file} symlink на ${expected_host_env_file}"
      fi
    elif [[ -f "$workspace_env_file" && -f "$expected_host_env_file" ]]; then
      flow_env_needs_repair="1"
      report_warn "FLOW_ENV_DUPLICATE_FILES" "${workspace_env_file};${expected_host_env_file}"
      report_action "FLOW_ENV_DUPLICATE_FILES" "Оставь source-of-truth в ${expected_host_env_file}, а ${workspace_env_file} замени symlink-ом"
    elif [[ -f "$workspace_env_file" ]]; then
      flow_env_needs_repair="1"
      report_warn "FLOW_ENV_WORKSPACE_LOCAL" "${workspace_env_file}"
      report_action "FLOW_ENV_WORKSPACE_LOCAL" "Если хочешь host-level source-of-truth, создай ${expected_host_env_file} и замени ${workspace_env_file} symlink-ом"
    elif [[ -f "$expected_host_env_file" ]]; then
      flow_env_needs_repair="1"
      report_warn "FLOW_ENV_WORKSPACE_MISSING" "${workspace_env_file}"
      report_action "FLOW_ENV_WORKSPACE_MISSING" "Создай symlink ${workspace_env_file} -> ${expected_host_env_file}"
    fi

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

    local actual_ops_remote_state_dir
    actual_ops_remote_state_dir="$(env_value "$env_file" "OPS_BOT_REMOTE_STATE_DIR")"
    if [[ "$actual_ops_remote_state_dir" == "$expected_remote_state_dir" ]]; then
      report_ok "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "$expected_remote_state_dir"
    else
      report_warn "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "expected:${expected_remote_state_dir};actual:${actual_ops_remote_state_dir}"
      report_action "OPS_BOT_REMOTE_STATE_DIR_LAYOUT" "Выстави OPS_BOT_REMOTE_STATE_DIR=${expected_remote_state_dir}"
      if [[ -n "$actual_ops_remote_state_dir" ]]; then
        array_append_unique "project_disable_keys" "OPS_BOT_REMOTE_STATE_DIR"
        array_append_unique "project_missing_core_keys" "OPS_BOT_REMOTE_STATE_DIR"
      fi
    fi
  fi

  if [[ "$fix_mode" == "1" ]]; then
    apply_fix_to_env_file "$env_file" "project" "project_disable_keys" "project_malformed_lines" "project_missing_core_keys" "project_missing_standard_keys"
    if [[ "$flow_env_needs_repair" == "1" && -n "${expected_host_env_file:-}" && -n "${workspace_env_file:-}" ]]; then
      repair_workspace_env_symlink "$workspace_env_file" "$expected_host_env_file"
      report_ok "FLOW_ENV_SYMLINK_FIXED" "${workspace_env_file} -> ${expected_host_env_file}"
    fi
  fi
}

platform_env_file="$(detect_platform_env_file)"

section "Env Audit"
report_ok "ROOT_DIR" "$ROOT_DIR"
report_ok "AI_FLOW_ROOT_DIR" "$(detect_ai_flow_root_dir)"

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
