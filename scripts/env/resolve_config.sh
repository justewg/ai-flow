#!/usr/bin/env bash

# Shared config resolver for flow automation scripts.
# shellcheck disable=SC2034
CODEX_CONFIG_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

codex_normalize_existing_dir() {
  local candidate="${1:-}"
  [[ -n "$candidate" && -d "$candidate" ]] || return 1
  cd "$candidate" && pwd -P
}

codex_discover_root_dir_from_pwd() {
  local current_dir parent_dir
  current_dir="$(codex_normalize_existing_dir "${PWD:-}" 2>/dev/null || true)"
  [[ -n "$current_dir" ]] || return 1

  while [[ -n "$current_dir" ]]; do
    if [[ -d "${current_dir}/.git" || -d "${current_dir}/.flow/config" || -L "${current_dir}/.flow/shared" || -d "${current_dir}/.flow/shared" ]]; then
      printf '%s' "$current_dir"
      return 0
    fi
    parent_dir="$(codex_normalize_existing_dir "${current_dir}/.." 2>/dev/null || true)"
    [[ "$parent_dir" != "$current_dir" ]] || break
    current_dir="$parent_dir"
  done

  return 1
}

codex_resolve_root_dir() {
  local discovered_root_dir
  discovered_root_dir="$(codex_discover_root_dir_from_pwd 2>/dev/null || true)"
  printf '%s' "${ROOT_DIR:-${CODEX_ROOT_DIR:-${discovered_root_dir:-$CODEX_CONFIG_ROOT_DIR}}}"
}

codex_resolve_bootstrap_value() {
  local key="$1"
  local default_value="${2:-}"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi
  printf '%s' "$default_value"
}

codex_resolve_flow_root_dir() {
  local root_dir
  root_dir="$(codex_resolve_root_dir)"
  codex_resolve_bootstrap_value "FLOW_ROOT_DIR" "${root_dir}/.flow"
}

codex_resolve_flow_scripts_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_bootstrap_value "FLOW_SCRIPTS_DIR" "${flow_root_dir}/scripts"
}

codex_resolve_flow_docs_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_bootstrap_value "FLOW_DOCS_DIR" "${flow_root_dir}/docs"
}

codex_resolve_flow_config_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_bootstrap_value "FLOW_CONFIG_DIR" "${flow_root_dir}/config"
}

codex_resolve_flow_profile_config_dir() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_bootstrap_value "FLOW_PROFILE_CONFIG_DIR" "${flow_config_dir}/profiles"
}

codex_resolve_flow_root_config_dir() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_bootstrap_value "FLOW_ROOT_CONFIG_DIR" "${flow_config_dir}/root"
}

codex_resolve_flow_env_file() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_bootstrap_value "FLOW_ENV_FILE" "${flow_config_dir}/flow.env"
}

codex_resolve_flow_sample_env_file() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_bootstrap_value "FLOW_SAMPLE_ENV_FILE" "${flow_config_dir}/flow.sample.env"
}

codex_resolve_flow_state_root_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_bootstrap_value "FLOW_STATE_ROOT_DIR" "${flow_root_dir}/state"
}

codex_resolve_ai_flow_state_root_dir() {
  local ai_flow_root_dir
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  codex_resolve_bootstrap_value "AI_FLOW_STATE_ROOT_DIR" "${ai_flow_root_dir}/state"
}

codex_resolve_flow_codex_state_root_dir() {
  local flow_state_root_dir
  flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
  codex_resolve_bootstrap_value "FLOW_CODEX_STATE_ROOT_DIR" "${flow_state_root_dir}"
}

codex_resolve_flow_logs_dir() {
  local value=""
  value="$(codex_try_config_value "FLOW_LOGS_DIR" || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  local ai_flow_logs_root_dir project_log_slug
  ai_flow_logs_root_dir="$(codex_resolve_ai_flow_logs_root_dir)"
  project_log_slug="$(codex_resolve_project_log_slug)"
  printf '%s/%s' "$ai_flow_logs_root_dir" "$project_log_slug"
}

codex_resolve_ai_flow_root_dir() {
  local root_dir sites_root_dir
  root_dir="$(codex_resolve_root_dir)"
  sites_root_dir="$(cd "${root_dir}/.." && pwd)"
  codex_resolve_bootstrap_value "AI_FLOW_ROOT_DIR" "${sites_root_dir}/.ai-flow"
}

codex_resolve_ai_flow_shared_dir() {
  local ai_flow_root_dir
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  codex_resolve_bootstrap_value "AI_FLOW_SHARED_DIR" "${ai_flow_root_dir}/shared"
}

codex_resolve_flow_shared_dir() {
  codex_resolve_ai_flow_shared_dir
}

codex_resolve_repo_flow_shared_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  printf '%s/shared' "$flow_root_dir"
}

codex_resolve_repo_flow_shared_scripts_dir() {
  local shared_dir
  shared_dir="$(codex_resolve_repo_flow_shared_dir)"
  printf '%s/scripts' "$shared_dir"
}

codex_resolve_flow_shared_scripts_dir() {
  local shared_dir
  shared_dir="$(codex_resolve_flow_shared_dir)"
  codex_resolve_bootstrap_value "FLOW_SHARED_SCRIPTS_DIR" "${shared_dir}/scripts"
}

codex_resolve_flow_shared_docs_dir() {
  local shared_dir
  shared_dir="$(codex_resolve_flow_shared_dir)"
  codex_resolve_bootstrap_value "FLOW_SHARED_DOCS_DIR" "${shared_dir}/docs"
}

codex_resolve_ai_flow_logs_root_dir() {
  local ai_flow_root_dir
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  codex_resolve_bootstrap_value "AI_FLOW_LOGS_ROOT_DIR" "${ai_flow_root_dir}/logs"
}

codex_resolve_ai_flow_launchd_root_dir() {
  local ai_flow_root_dir
  ai_flow_root_dir="$(codex_resolve_ai_flow_root_dir)"
  codex_resolve_bootstrap_value "AI_FLOW_LAUNCHD_ROOT_DIR" "${ai_flow_root_dir}/launchd"
}

codex_slugify_value() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="default"
  printf '%s' "$value"
}

codex_resolve_project_namespace_slug() {
  local value profile_name repo_slug repo_name
  value="$(codex_try_config_value "FLOW_LOG_NAMESPACE" || true)"
  if [[ -n "$value" ]]; then
    codex_slugify_value "$value"
    return 0
  fi

  profile_name="$(codex_try_config_value "PROJECT_PROFILE" || true)"
  if [[ -n "$profile_name" && "$profile_name" != "default" ]]; then
    codex_slugify_value "$profile_name"
    return 0
  fi

  repo_slug="$(codex_try_config_value "GITHUB_REPO" || true)"
  repo_name="${repo_slug##*/}"
  if [[ -n "$repo_name" && "$repo_name" != "$repo_slug" ]]; then
    codex_slugify_value "$repo_name"
    return 0
  fi

  codex_slugify_value "default"
}

codex_resolve_project_log_slug() {
  codex_resolve_project_namespace_slug
}

codex_resolve_flow_runtime_log_dir() {
  local flow_logs_dir
  flow_logs_dir="$(codex_resolve_flow_logs_dir)"
  codex_resolve_bootstrap_value "FLOW_RUNTIME_LOG_DIR" "${flow_logs_dir}/runtime"
}

codex_resolve_flow_pm2_log_dir() {
  local flow_logs_dir
  flow_logs_dir="$(codex_resolve_flow_logs_dir)"
  codex_resolve_bootstrap_value "FLOW_PM2_LOG_DIR" "${flow_logs_dir}/pm2"
}

codex_resolve_flow_tmp_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_bootstrap_value "FLOW_TMP_DIR" "${flow_root_dir}/tmp"
}

codex_resolve_flow_launchd_dir() {
  local value="" ai_flow_launchd_root_dir project_namespace_slug
  value="$(codex_try_config_value "FLOW_LAUNCHD_DIR" || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  ai_flow_launchd_root_dir="$(codex_resolve_ai_flow_launchd_root_dir)"
  project_namespace_slug="$(codex_resolve_project_namespace_slug)"
  printf '%s/%s' "$ai_flow_launchd_root_dir" "$project_namespace_slug"
}

codex_resolve_flow_launchagents_dir() {
  codex_resolve_bootstrap_value "FLOW_LAUNCHAGENTS_DIR" "${HOME}/Library/LaunchAgents"
}

codex_resolve_flow_launchd_namespace() {
  codex_resolve_bootstrap_value "FLOW_LAUNCHD_NAMESPACE" "com.flow"
}

codex_resolve_default_daemon_label() {
  local launchd_namespace profile_slug
  launchd_namespace="$(codex_resolve_flow_launchd_namespace)"
  profile_slug="$(codex_resolve_project_namespace_slug)"
  printf '%s.codex-daemon.%s' "$launchd_namespace" "$profile_slug"
}

codex_resolve_default_watchdog_label() {
  local launchd_namespace profile_slug
  launchd_namespace="$(codex_resolve_flow_launchd_namespace)"
  profile_slug="$(codex_resolve_project_namespace_slug)"
  printf '%s.codex-watchdog.%s' "$launchd_namespace" "$profile_slug"
}

codex_strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

codex_read_key_from_env_file() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 1
  local raw
  raw="$(grep -E "^${key}=" "$file_path" | tail -n1 | cut -d'=' -f2- || true)"
  [[ -n "$raw" ]] || return 1
  codex_strip_quotes "$raw"
}

codex_load_env_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file_path"
    set +a
  fi
}

codex_detect_legacy_profile_env_file() {
  local explicit_profile="${1:-}"
  local profile_config_dir flow_env_file default_profile_file detected=""
  profile_config_dir="$(codex_resolve_flow_profile_config_dir)"
  flow_env_file="$(codex_resolve_flow_env_file)"
  [[ -d "$profile_config_dir" ]] || return 1

  if [[ -n "$explicit_profile" ]]; then
    detected="${profile_config_dir}/${explicit_profile}.env"
    [[ -f "$detected" ]] && { printf '%s' "$detected"; return 0; }
  fi

  if [[ -n "${PROJECT_PROFILE:-}" ]]; then
    detected="${profile_config_dir}/${PROJECT_PROFILE}.env"
    [[ -f "$detected" ]] && { printf '%s' "$detected"; return 0; }
  fi

  detected="${profile_config_dir}/default.env"
  if [[ -f "$detected" && "$detected" != "$flow_env_file" ]]; then
    printf '%s' "$detected"
    return 0
  fi

  local count=0 first=""
  while IFS= read -r detected; do
    [[ -n "$detected" ]] || continue
    [[ "$detected" == "$flow_env_file" ]] && continue
    count=$((count + 1))
    if [[ "$count" == "1" ]]; then
      first="$detected"
    fi
  done <<EOF
$(find "$profile_config_dir" -maxdepth 1 -type f -name '*.env' | sort)
EOF

  if [[ "$count" == "1" && -n "$first" ]]; then
    printf '%s' "$first"
    return 0
  fi

  return 1
}

codex_collect_env_files() {
  local explicit_profile="${1:-}"
  local root_dir flow_env_file legacy_env_file
  root_dir="$(codex_resolve_root_dir)"
  flow_env_file="$(codex_resolve_flow_env_file)"
  legacy_env_file="$(codex_detect_legacy_profile_env_file "$explicit_profile" || true)"

  if [[ -n "$legacy_env_file" && "$legacy_env_file" != "$flow_env_file" ]]; then
    printf '%s\n' "$legacy_env_file"
  fi
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" && "${DAEMON_GH_ENV_FILE}" != "$flow_env_file" ]]; then
    printf '%s\n' "${DAEMON_GH_ENV_FILE}"
  fi
  printf '%s\n' "$flow_env_file"
  printf '%s\n' "${root_dir}/.env"
  printf '%s\n' "${root_dir}/.env.deploy"
}

codex_load_flow_env() {
  local explicit_profile="${1:-}"
  local env_file
  while IFS= read -r env_file; do
    [[ -n "$env_file" ]] || continue
    [[ -f "$env_file" ]] || continue
    codex_load_env_file "$env_file"
  done <<EOF
$(codex_collect_env_files "$explicit_profile")
EOF
}

codex_try_config_value() {
  local key="$1"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi

  local env_file value
  while IFS= read -r env_file; do
    [[ -n "$env_file" ]] || continue
    value="$(codex_read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done <<EOF
$(codex_collect_env_files)
EOF

  return 1
}

codex_resolve_config_value() {
  local key="$1"
  local default_value="${2:-}"
  local value

  value="$(codex_try_config_value "$key" || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s' "$default_value"
}

codex_resolve_state_dir() {
  local default_state_dir
  local value=""

  default_state_dir="$(codex_resolve_flow_state_root_dir)"

  value="$(codex_try_config_value "CODEX_STATE_DIR" || true)"
  if [[ -z "$value" ]]; then
    value="$(codex_try_config_value "FLOW_STATE_DIR" || true)"
  fi

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s' "$default_state_dir"
}

codex_resolve_state_namespace_dir() {
  local namespace="$1"
  local state_dir="${2:-}"
  [[ -n "$state_dir" ]] || state_dir="$(codex_resolve_state_dir)"
  printf '%s/%s' "$state_dir" "$namespace"
}

codex_resolve_state_daemon_dir() { codex_resolve_state_namespace_dir "daemon" "${1:-}"; }
codex_resolve_state_watchdog_dir() { codex_resolve_state_namespace_dir "watchdog" "${1:-}"; }
codex_resolve_state_executor_dir() { codex_resolve_state_namespace_dir "executor" "${1:-}"; }
codex_resolve_state_project_dir() { codex_resolve_state_namespace_dir "project" "${1:-}"; }
codex_resolve_state_github_dir() { codex_resolve_state_namespace_dir "github" "${1:-}"; }
codex_resolve_state_ops_dir() { codex_resolve_state_namespace_dir "ops" "${1:-}"; }
codex_resolve_state_inputs_dir() { codex_resolve_state_namespace_dir "inputs" "${1:-}"; }
codex_resolve_state_queue_dir() { codex_resolve_state_namespace_dir "queue" "${1:-}"; }
codex_resolve_state_outbox_dir() {
  local state_dir="${1:-}"
  [[ -n "$state_dir" ]] || state_dir="$(codex_resolve_state_dir)"
  printf '%s/outbox' "$(codex_resolve_state_queue_dir "$state_dir")"
}
codex_resolve_state_outbox_failed_dir() {
  local state_dir="${1:-}"
  [[ -n "$state_dir" ]] || state_dir="$(codex_resolve_state_dir)"
  printf '%s/outbox_failed' "$(codex_resolve_state_queue_dir "$state_dir")"
}
codex_resolve_state_outbox_payload_dir() {
  local state_dir="${1:-}"
  [[ -n "$state_dir" ]] || state_dir="$(codex_resolve_state_dir)"
  printf '%s/outbox_payloads' "$(codex_resolve_state_queue_dir "$state_dir")"
}
codex_resolve_state_tmp_dir() { codex_resolve_state_namespace_dir "tmp" "${1:-}"; }

codex_resolve_profile_env_file() {
  local profile_name="${1:-default}"
  local profile_config_dir
  profile_config_dir="$(codex_resolve_flow_profile_config_dir)"
  printf '%s/%s.env' "$profile_config_dir" "$profile_name"
}

codex_export_state_dir() {
  local state_dir="${1:-}"

  if [[ -z "$state_dir" ]]; then
    state_dir="$(codex_resolve_state_dir)"
  fi

  CODEX_STATE_DIR="$state_dir"
  FLOW_STATE_DIR="$state_dir"
  export CODEX_STATE_DIR FLOW_STATE_DIR
  printf '%s' "$state_dir"
}

codex_resolve_flow_config() {
  FLOW_GITHUB_REPO="$(codex_resolve_config_value "GITHUB_REPO" "justewg/planka")"
  FLOW_BASE_BRANCH="$(codex_resolve_config_value "FLOW_BASE_BRANCH" "main")"
  FLOW_HEAD_BRANCH="$(codex_resolve_config_value "FLOW_HEAD_BRANCH" "development")"
  FLOW_REPO_OWNER="${FLOW_GITHUB_REPO%%/*}"
}

codex_resolve_project_profile_name() {
  codex_resolve_config_value "PROJECT_PROFILE" "default"
}

codex_resolve_project_repo_slug() {
  codex_resolve_config_value "GITHUB_REPO" "justewg/planka"
}

codex_resolve_project_repo_name() {
  local repo_slug
  repo_slug="$(codex_resolve_project_repo_slug)"
  printf '%s' "${repo_slug##*/}"
}

codex_resolve_project_display_label() {
  local profile_name repo_slug repo_name
  profile_name="$(codex_resolve_project_profile_name)"
  repo_slug="$(codex_resolve_project_repo_slug)"
  repo_name="${repo_slug##*/}"

  if [[ -z "$profile_name" || "$profile_name" == "default" ]]; then
    printf '%s' "$repo_slug"
    return 0
  fi

  if [[ "$profile_name" == "$repo_name" ]]; then
    printf '%s' "$repo_slug"
    return 0
  fi

  printf '%s · %s' "$profile_name" "$repo_slug"
}

codex_resolve_project_config() {
  local default_project_id="PVT_kwHOAPt_Q84BPyyr"
  local default_project_number="2"
  local default_project_owner="@me"
  local project_profile configured_count
  local configured_project_id=""
  local configured_project_number=""
  local configured_project_owner=""
  local -a missing_keys=()

  project_profile="$(codex_resolve_config_value "PROJECT_PROFILE" "default")"
  configured_count=0
  configured_project_id="$(codex_try_config_value "PROJECT_ID" || true)"
  configured_project_number="$(codex_try_config_value "PROJECT_NUMBER" || true)"
  configured_project_owner="$(codex_try_config_value "PROJECT_OWNER" || true)"

  [[ -n "$configured_project_id" ]] && configured_count=$((configured_count + 1))
  [[ -n "$configured_project_number" ]] && configured_count=$((configured_count + 1))
  [[ -n "$configured_project_owner" ]] && configured_count=$((configured_count + 1))

  if [[ "$project_profile" == "default" && "$configured_count" -gt 0 && "$configured_count" -lt 3 ]]; then
    [[ -n "$configured_project_id" ]] || missing_keys+=("PROJECT_ID")
    [[ -n "$configured_project_number" ]] || missing_keys+=("PROJECT_NUMBER")
    [[ -n "$configured_project_owner" ]] || missing_keys+=("PROJECT_OWNER")
    echo "Custom Project binding requires PROJECT_ID, PROJECT_NUMBER and PROJECT_OWNER together." >&2
    echo "PROJECT_PROFILE=default" >&2
    echo "Missing: ${missing_keys[*]}" >&2
    echo "Provide all three variables to switch projects, or remove partial overrides to use the default binding." >&2
    return 1
  fi

  PROJECT_PROFILE="$project_profile"

  if [[ "$PROJECT_PROFILE" != "default" ]]; then
    [[ -n "$configured_project_id" ]] || missing_keys+=("PROJECT_ID")
    [[ -n "$configured_project_number" ]] || missing_keys+=("PROJECT_NUMBER")
    [[ -n "$configured_project_owner" ]] || missing_keys+=("PROJECT_OWNER")
    if [[ "${#missing_keys[@]}" -gt 0 ]]; then
      echo "Non-default Project profile requires explicit PROJECT_ID, PROJECT_NUMBER and PROJECT_OWNER." >&2
      echo "PROJECT_PROFILE=${PROJECT_PROFILE}" >&2
      echo "Missing: ${missing_keys[*]}" >&2
      return 1
    fi
    PROJECT_ID="$configured_project_id"
    PROJECT_NUMBER="$configured_project_number"
    PROJECT_OWNER="$configured_project_owner"
    return 0
  fi

  PROJECT_ID="${configured_project_id:-$default_project_id}"
  PROJECT_NUMBER="${configured_project_number:-$default_project_number}"
  PROJECT_OWNER="${configured_project_owner:-$default_project_owner}"
}

codex_emit_branch_mismatch_markers() {
  local marker_prefix="$1"
  local current_branch="$2"

  if [[ "$current_branch" != "$FLOW_HEAD_BRANCH" ]]; then
    echo "${marker_prefix}_BRANCH_MISMATCH=1"
    echo "${marker_prefix}_EXPECTED_HEAD_BRANCH=${FLOW_HEAD_BRANCH}"
    echo "${marker_prefix}_CURRENT_BRANCH=${current_branch:-unknown}"
    return 1
  fi

  echo "${marker_prefix}_BRANCH_MISMATCH=0"
  return 0
}
