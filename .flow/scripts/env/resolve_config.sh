#!/usr/bin/env bash

# Shared config resolver for flow automation scripts.
# shellcheck disable=SC2034
CODEX_CONFIG_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

codex_resolve_root_dir() {
  printf '%s' "${ROOT_DIR:-${CODEX_ROOT_DIR:-$CODEX_CONFIG_ROOT_DIR}}"
}

codex_resolve_flow_root_dir() {
  local root_dir
  root_dir="$(codex_resolve_root_dir)"
  codex_resolve_config_value "FLOW_ROOT_DIR" "${root_dir}/.flow"
}

codex_resolve_flow_scripts_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_SCRIPTS_DIR" "${flow_root_dir}/scripts"
}

codex_resolve_flow_docs_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_DOCS_DIR" "${flow_root_dir}/docs"
}

codex_resolve_flow_config_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_CONFIG_DIR" "${flow_root_dir}/config"
}

codex_resolve_flow_profile_config_dir() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_config_value "FLOW_PROFILE_CONFIG_DIR" "${flow_config_dir}/profiles"
}

codex_resolve_flow_root_config_dir() {
  local flow_config_dir
  flow_config_dir="$(codex_resolve_flow_config_dir)"
  codex_resolve_config_value "FLOW_ROOT_CONFIG_DIR" "${flow_config_dir}/root"
}

codex_resolve_flow_state_root_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_STATE_ROOT_DIR" "${flow_root_dir}/state"
}

codex_resolve_flow_codex_state_root_dir() {
  local flow_state_root_dir
  flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
  codex_resolve_config_value "FLOW_CODEX_STATE_ROOT_DIR" "${flow_state_root_dir}/codex"
}

codex_resolve_flow_logs_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_LOGS_DIR" "${flow_root_dir}/logs"
}

codex_resolve_flow_pm2_log_dir() {
  local flow_logs_dir
  flow_logs_dir="$(codex_resolve_flow_logs_dir)"
  codex_resolve_config_value "FLOW_PM2_LOG_DIR" "${flow_logs_dir}/pm2"
}

codex_resolve_flow_tmp_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_TMP_DIR" "${flow_root_dir}/tmp"
}

codex_resolve_flow_launchd_dir() {
  local flow_root_dir
  flow_root_dir="$(codex_resolve_flow_root_dir)"
  codex_resolve_config_value "FLOW_LAUNCHD_DIR" "${flow_root_dir}/launchd"
}

codex_resolve_flow_launchagents_dir() {
  codex_resolve_config_value "FLOW_LAUNCHAGENTS_DIR" "${HOME}/Library/LaunchAgents"
}

codex_resolve_flow_launchd_namespace() {
  codex_resolve_config_value "FLOW_LAUNCHD_NAMESPACE" "com.flow"
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

codex_try_config_value() {
  local key="$1"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi

  local root_dir
  local flow_root_dir
  local flow_config_dir
  local flow_root_config_dir
  root_dir="$(codex_resolve_root_dir)"
  flow_root_dir="${FLOW_ROOT_DIR:-${root_dir}/.flow}"
  flow_config_dir="${FLOW_CONFIG_DIR:-${flow_root_dir}/config}"
  flow_root_config_dir="${FLOW_ROOT_CONFIG_DIR:-${flow_config_dir}/root}"
  local -a env_candidates=()
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" ]]; then
    env_candidates+=("${DAEMON_GH_ENV_FILE}")
  fi
  env_candidates+=("${root_dir}/.env")
  env_candidates+=("${root_dir}/.env.deploy")
  env_candidates+=("${flow_root_config_dir}/.env.codex")

  local env_file value
  for env_file in "${env_candidates[@]}"; do
    value="$(codex_read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

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

  default_state_dir="$(codex_resolve_flow_codex_state_root_dir)/default"

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
