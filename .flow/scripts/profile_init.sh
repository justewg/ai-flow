#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"

usage() {
  cat <<'EOF'
Usage: .flow/scripts/profile_init.sh <init|install|preflight|bootstrap> [options]

Modes:
  init        Создать env template, state-dir и расчетные launchd labels.
  install     Провалидировать env и установить daemon/watchdog для профиля.
  preflight   Вывести health/smoke checklist для профиля.
  bootstrap   Последовательно выполнить init -> install -> preflight.

Options:
  --profile <name>             Имя project profile (обязательно).
  --env-file <path>            Путь к project-scoped flow env-файлу.
  --state-dir <path>           Путь к profile state-dir.
  --project-profile <name>     Значение PROJECT_PROFILE (по умолчанию = profile).
  --daemon-label <label>       Launchd label daemon.
  --watchdog-label <label>     Launchd label watchdog.
  --daemon-interval <sec>      Интервал daemon (по умолчанию 45).
  --watchdog-interval <sec>    Интервал watchdog (по умолчанию 45).
  --force                      Перезаписать env template при init.
  --dry-run                    Ничего не менять, только показать действия.

Examples:
  .flow/scripts/profile_init.sh init --profile acme
  .flow/scripts/profile_init.sh install --profile acme
  .flow/scripts/profile_init.sh preflight --profile acme
  .flow/scripts/profile_init.sh bootstrap --profile acme --dry-run
EOF
}

mode="${1:-}"
if [[ -z "$mode" ]]; then
  usage
  exit 1
fi
case "$mode" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac
shift || true

profile=""
env_file=""
state_dir=""
project_profile=""
daemon_label=""
watchdog_label=""
daemon_interval="45"
watchdog_interval="45"
force="0"
dry_run="0"

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="profile"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --env-file" >&2; exit 1; }
      env_file="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-dir" >&2; exit 1; }
      state_dir="$2"
      shift 2
      ;;
    --project-profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --project-profile" >&2; exit 1; }
      project_profile="$2"
      shift 2
      ;;
    --daemon-label)
      [[ $# -ge 2 ]] || { echo "Missing value for --daemon-label" >&2; exit 1; }
      daemon_label="$2"
      shift 2
      ;;
    --watchdog-label)
      [[ $# -ge 2 ]] || { echo "Missing value for --watchdog-label" >&2; exit 1; }
      watchdog_label="$2"
      shift 2
      ;;
    --daemon-interval)
      [[ $# -ge 2 ]] || { echo "Missing value for --daemon-interval" >&2; exit 1; }
      daemon_interval="$2"
      shift 2
      ;;
    --watchdog-interval)
      [[ $# -ge 2 ]] || { echo "Missing value for --watchdog-interval" >&2; exit 1; }
      watchdog_interval="$2"
      shift 2
      ;;
    --force)
      force="1"
      shift
      ;;
    --dry-run)
      dry_run="1"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$profile" ]]; then
  echo "Option --profile is required" >&2
  usage
  exit 1
fi

profile_slug="$(slugify "$profile")"
flow_codex_state_root_dir="$(codex_resolve_flow_codex_state_root_dir)"
flow_env_file="$(codex_resolve_flow_env_file)"
flow_sample_env_file="$(codex_resolve_flow_sample_env_file)"
launchd_namespace="$(codex_resolve_flow_launchd_namespace)"
[[ -n "$project_profile" ]] || project_profile="$profile_slug"
[[ -n "$env_file" ]] || env_file="${flow_env_file}"
[[ -n "$state_dir" ]] || state_dir="${flow_codex_state_root_dir}/${profile_slug}"
[[ -n "$daemon_label" ]] || daemon_label="${launchd_namespace}.codex-daemon.${profile_slug}"
[[ -n "$watchdog_label" ]] || watchdog_label="${launchd_namespace}.codex-watchdog.${profile_slug}"

if ! [[ "$daemon_interval" =~ ^[0-9]+$ ]] || (( daemon_interval < 5 )); then
  echo "Invalid --daemon-interval: ${daemon_interval} (expected integer >= 5)" >&2
  exit 1
fi

if ! [[ "$watchdog_interval" =~ ^[0-9]+$ ]] || (( watchdog_interval < 10 )); then
  echo "Invalid --watchdog-interval: ${watchdog_interval} (expected integer >= 10)" >&2
  exit 1
fi

emit_profile_summary() {
  cat <<EOF
PROFILE=${profile}
PROFILE_SLUG=${profile_slug}
PROJECT_PROFILE=${project_profile}
ENV_FILE=${env_file}
SAMPLE_ENV_FILE=${flow_sample_env_file}
STATE_DIR=${state_dir}
DAEMON_LABEL=${daemon_label}
DAEMON_INTERVAL=${daemon_interval}
WATCHDOG_LABEL=${watchdog_label}
WATCHDOG_INTERVAL=${watchdog_interval}
EOF
}

template_contents() {
  cat <<EOF
# Generated by .flow/scripts/profile_init.sh for profile ${profile}
# Fill required values in .flow/config/flow.env before running install/preflight.

PROJECT_PROFILE=${project_profile}
GITHUB_REPO=
FLOW_BASE_BRANCH=main
FLOW_HEAD_BRANCH=development

# PROJECT_NUMBER и PROJECT_OWNER возьми из URL Project v2 в GitHub UI:
#   https://github.com/users/<owner>/projects/<number>
#   https://github.com/orgs/<owner>/projects/<number>
# Либо выведи все проекты owner с title/number/id:
#   gh project list --owner <PROJECT_OWNER> --format json --jq '.projects[] | [.owner.login, .title, (.number|tostring), .id] | @tsv'
# PROJECT_ID (node id, вида PVT_...) GitHub UI не показывает.
# Получить его можно так:
#   gh project view <PROJECT_NUMBER> --owner <PROJECT_OWNER> --format json --jq '.id'
PROJECT_ID=
PROJECT_NUMBER=
PROJECT_OWNER=

# Required for Project v2 operations in the current hybrid flow.
# GitHub UI:
#   Avatar -> Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token
# Required scopes:
#   repo, read:project, project
# Recommended extra scopes for compatibility:
#   read:org, read:discussions
DAEMON_GH_PROJECT_TOKEN=

# Required for daemon/watchdog -> auth-service token exchange.
# Alternative: set DAEMON_GH_TOKEN_FALLBACK_ENABLED=1 and DAEMON_GH_TOKEN.
GH_APP_INTERNAL_SECRET=

# GitHub App auth-service
FLOW_LAUNCHD_NAMESPACE=${launchd_namespace}
GH_APP_ID=
GH_APP_INSTALLATION_ID=
# Recommended neutral path outside repo:
# GH_APP_PRIVATE_KEY_PATH=<HOME>/.secrets/gh-apps/codex-flow.private-key.pem
GH_APP_PRIVATE_KEY_PATH=
GH_APP_OWNER=
GH_APP_REPO=
GH_APP_BIND=127.0.0.1
GH_APP_PORT=8787
GH_APP_TOKEN_SKEW_SEC=300
GH_APP_PM2_APP_NAME=${project_profile}-gh-app-auth
GH_APP_PM2_USE_DEFAULT=1
DAEMON_GH_AUTH_TIMEOUT_SEC=8
DAEMON_GH_AUTH_TOKEN_URL=

# Optional emergency fallback token.
DAEMON_GH_TOKEN_FALLBACK_ENABLED=0
DAEMON_GH_TOKEN=

# Local daemon/watchdog Telegram alerts
DAEMON_TG_BOT_TOKEN=
DAEMON_TG_CHAT_ID=
DAEMON_TG_REMINDER_SEC=1800
DAEMON_TG_GH_DNS_REMINDER_SEC=300
DAEMON_TG_DIRTY_REMINDER_SEC=600

# Ops bot + status dashboard
OPS_BOT_USE_DEFAULT=1
OPS_BOT_BIND=127.0.0.1
OPS_BOT_PORT=8790
OPS_BOT_WEBHOOK_PATH=/telegram/webhook
OPS_BOT_WEBHOOK_SECRET=
OPS_BOT_TG_SECRET_TOKEN=
OPS_BOT_ALLOWED_CHAT_IDS=
OPS_BOT_PUBLIC_BASE_URL=
OPS_BOT_REFRESH_SEC=5
OPS_BOT_CMD_TIMEOUT_MS=10000
OPS_BOT_PM2_APP_NAME=${project_profile}-ops-bot
OPS_BOT_TG_BOT_TOKEN=

# Optional split-runtime mode: remote ops bot accepts snapshot/log-summary from local daemon runtime
# OPS_BOT_INGEST_ENABLED=1
# OPS_BOT_INGEST_PATH=/ops/ingest/status
# OPS_BOT_INGEST_SECRET=
# OPS_BOT_SUMMARY_INGEST_PATH=/ops/ingest/log-summary
# OPS_BOT_SUMMARY_INGEST_SECRET=
OPS_BOT_REMOTE_STATE_DIR=.flow/state/ops-bot/remote
OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC=600
OPS_BOT_REMOTE_SUMMARY_TTL_SEC=1200
# OPS_REMOTE_STATUS_PUSH_ENABLED=1
# OPS_REMOTE_STATUS_PUSH_URL=
# OPS_REMOTE_STATUS_PUSH_SECRET=
# OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC=6
# OPS_REMOTE_STATUS_PUSH_SOURCE=${project_profile}
# OPS_REMOTE_SUMMARY_PUSH_ENABLED=1
# OPS_REMOTE_SUMMARY_PUSH_URL=
# OPS_REMOTE_SUMMARY_PUSH_SECRET=
# OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC=8
# OPS_REMOTE_SUMMARY_PUSH_SOURCE=${project_profile}
# OPS_REMOTE_SUMMARY_PUSH_HOURS=6
# OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC=300

CODEX_STATE_DIR=${state_dir}
FLOW_STATE_DIR=${state_dir}

# Needed so watchdog can restart the correct daemon profile.
WATCHDOG_DAEMON_LABEL=${daemon_label}
WATCHDOG_DAEMON_INTERVAL_SEC=${daemon_interval}
EOF
}

ensure_dir() {
  local dir_path="$1"
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN mkdir -p %s\n' "$dir_path"
    return 0
  fi
  mkdir -p "$dir_path"
}

init_profile() {
  emit_profile_summary
  ensure_dir "$(dirname "$env_file")"
  ensure_dir "$state_dir"

  if [[ -f "$env_file" && "$force" != "1" ]]; then
    if [[ ! -f "$flow_sample_env_file" ]]; then
      if [[ "$dry_run" == "1" ]]; then
        echo "DRY_RUN write ${flow_sample_env_file}"
      else
        ensure_dir "$(dirname "$flow_sample_env_file")"
        template_contents > "$flow_sample_env_file"
        echo "FLOW_SAMPLE_ENV_WRITTEN=${flow_sample_env_file}"
      fi
    fi
    echo "ENV_TEMPLATE_EXISTS=${env_file}"
    echo "ENV_TEMPLATE_OVERWRITE=0"
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "DRY_RUN write ${env_file}"
    template_contents
    return 0
  fi

  template_contents > "$env_file"
  if [[ "$flow_sample_env_file" != "$env_file" ]]; then
    template_contents > "$flow_sample_env_file"
    echo "FLOW_SAMPLE_ENV_WRITTEN=${flow_sample_env_file}"
  fi
  echo "ENV_TEMPLATE_WRITTEN=${env_file}"
  echo "STATE_DIR_READY=${state_dir}"
}

read_profile_value() {
  local key="$1"
  codex_read_key_from_env_file "$env_file" "$key" || true
}

is_truthy() {
  local raw_value="${1:-}"
  raw_value="$(printf '%s' "$raw_value" | tr '[:upper:]' '[:lower:]')"
  case "$raw_value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

validation_failed="0"

report_ok() {
  printf 'CHECK_OK %s=%s\n' "$1" "$2"
}

report_fail() {
  validation_failed="1"
  printf 'CHECK_FAIL %s=%s\n' "$1" "$2" >&2
}

validate_required_env() {
  validation_failed="0"

  if [[ ! -f "$env_file" ]]; then
    report_fail "ENV_FILE" "missing:${env_file}"
    return 1
  fi

  local repo base_branch head_branch project_profile_value project_id project_number project_owner
  local project_token fallback_enabled fallback_token auth_secret state_dir_value

  repo="$(read_profile_value "GITHUB_REPO")"
  base_branch="$(read_profile_value "FLOW_BASE_BRANCH")"
  head_branch="$(read_profile_value "FLOW_HEAD_BRANCH")"
  project_profile_value="$(read_profile_value "PROJECT_PROFILE")"
  project_id="$(read_profile_value "PROJECT_ID")"
  project_number="$(read_profile_value "PROJECT_NUMBER")"
  project_owner="$(read_profile_value "PROJECT_OWNER")"
  project_token="$(read_profile_value "DAEMON_GH_PROJECT_TOKEN")"
  [[ -n "$project_token" ]] || project_token="$(read_profile_value "CODEX_GH_PROJECT_TOKEN")"
  fallback_enabled="$(read_profile_value "DAEMON_GH_TOKEN_FALLBACK_ENABLED")"
  fallback_token="$(read_profile_value "DAEMON_GH_TOKEN")"
  [[ -n "$fallback_token" ]] || fallback_token="$(read_profile_value "CODEX_GH_TOKEN")"
  auth_secret="$(read_profile_value "GH_APP_INTERNAL_SECRET")"
  state_dir_value="$(read_profile_value "CODEX_STATE_DIR")"
  [[ -n "$state_dir_value" ]] || state_dir_value="$(read_profile_value "FLOW_STATE_DIR")"

  [[ -n "$repo" ]] && report_ok "GITHUB_REPO" "$repo" || report_fail "GITHUB_REPO" "empty"
  [[ -n "$base_branch" ]] && report_ok "FLOW_BASE_BRANCH" "$base_branch" || report_fail "FLOW_BASE_BRANCH" "empty"
  [[ -n "$head_branch" ]] && report_ok "FLOW_HEAD_BRANCH" "$head_branch" || report_fail "FLOW_HEAD_BRANCH" "empty"
  [[ -n "$project_profile_value" ]] && report_ok "PROJECT_PROFILE" "$project_profile_value" || report_fail "PROJECT_PROFILE" "empty"
  [[ -n "$project_id" ]] && report_ok "PROJECT_ID" "$project_id" || report_fail "PROJECT_ID" "empty"
  [[ -n "$project_number" ]] && report_ok "PROJECT_NUMBER" "$project_number" || report_fail "PROJECT_NUMBER" "empty"
  [[ -n "$project_owner" ]] && report_ok "PROJECT_OWNER" "$project_owner" || report_fail "PROJECT_OWNER" "empty"
  [[ -n "$project_token" ]] && report_ok "PROJECT_TOKEN" "present" || report_fail "PROJECT_TOKEN" "missing:DAEMON_GH_PROJECT_TOKEN|CODEX_GH_PROJECT_TOKEN"
  [[ -n "$state_dir_value" ]] && report_ok "STATE_DIR_ENV" "$state_dir_value" || report_fail "STATE_DIR_ENV" "missing:CODEX_STATE_DIR|FLOW_STATE_DIR"

  if [[ -n "$auth_secret" ]]; then
    report_ok "AUTOMATION_AUTH" "GH_APP_INTERNAL_SECRET"
  elif is_truthy "$fallback_enabled" && [[ -n "$fallback_token" ]]; then
    report_ok "AUTOMATION_AUTH" "PAT_FALLBACK"
  else
    report_fail "AUTOMATION_AUTH" "missing:GH_APP_INTERNAL_SECRET or fallback token pair"
  fi

  [[ "$validation_failed" == "0" ]]
}

status_summary() {
  local label="$1"
  local script_path="$2"
  local out
  if out="$("$script_path" "$label" 2>&1)"; then
    printf '%s' "$out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//'
    return 0
  fi
  printf '%s' "$out" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//'
  return 1
}

install_profile() {
  emit_profile_summary
  if [[ "$dry_run" == "1" && ! -f "$env_file" ]]; then
    echo "CHECK_WARN ENV_FILE=missing:${env_file}"
    ensure_dir "$state_dir"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "${ROOT_DIR}/.flow/scripts/daemon_install.sh" "$daemon_label" "$daemon_interval"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s WATCHDOG_DAEMON_LABEL=%s WATCHDOG_DAEMON_INTERVAL_SEC=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "$daemon_label" "$daemon_interval" "${ROOT_DIR}/.flow/scripts/watchdog_install.sh" "$watchdog_label" "$watchdog_interval"
    echo "INSTALL_DRY_RUN_ONLY=1"
    return 0
  fi

  validate_required_env
  if [[ "$validation_failed" != "0" ]]; then
    echo "INSTALL_ABORTED=1"
    return 1
  fi

  ensure_dir "$state_dir"

  local daemon_cmd=("${ROOT_DIR}/.flow/scripts/daemon_install.sh" "$daemon_label" "$daemon_interval")
  local watchdog_cmd=("${ROOT_DIR}/.flow/scripts/watchdog_install.sh" "$watchdog_label" "$watchdog_interval")

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "${daemon_cmd[0]}" "${daemon_cmd[1]}" "${daemon_cmd[2]}"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s WATCHDOG_DAEMON_LABEL=%s WATCHDOG_DAEMON_INTERVAL_SEC=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "$daemon_label" "$daemon_interval" "${watchdog_cmd[0]}" "${watchdog_cmd[1]}" "${watchdog_cmd[2]}"
    return 0
  fi

  DAEMON_GH_ENV_FILE="$env_file" CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" \
    "${daemon_cmd[@]}"
  DAEMON_GH_ENV_FILE="$env_file" CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" \
    WATCHDOG_DAEMON_LABEL="$daemon_label" WATCHDOG_DAEMON_INTERVAL_SEC="$daemon_interval" \
    "${watchdog_cmd[@]}"
}

preflight_profile() {
  emit_profile_summary
  if [[ "$dry_run" == "1" && ! -f "$env_file" ]]; then
    echo "CHECK_WARN ENV_FILE=missing:${env_file}"
    echo "CHECKLIST daemon_status=SKIPPED_DRY_RUN"
    echo "CHECKLIST watchdog_status=SKIPPED_DRY_RUN"
    echo "CHECKLIST state_dir_exists=0"
    echo "CHECKLIST env_file_exists=0"
    cat <<EOF
SMOKE_STEP 1 .flow/scripts/run.sh profile_init init --profile ${profile} --env-file ${env_file} --state-dir ${state_dir}
SMOKE_STEP 2 fill required env in ${env_file}
SMOKE_STEP 3 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh profile_init install --profile ${profile}
SMOKE_STEP 4 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh github_health_check
SMOKE_STEP 5 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh status_snapshot
EOF
    echo "PREFLIGHT_READY=0"
    return 0
  fi

  validate_required_env || true

  local daemon_status watchdog_status
  daemon_status="$(status_summary "$daemon_label" "${ROOT_DIR}/.flow/scripts/daemon_status.sh")"
  watchdog_status="$(status_summary "$watchdog_label" "${ROOT_DIR}/.flow/scripts/watchdog_status.sh")"

  echo "CHECKLIST daemon_status=${daemon_status}"
  echo "CHECKLIST watchdog_status=${watchdog_status}"
  if [[ -d "$state_dir" ]]; then
    echo "CHECKLIST state_dir_exists=1"
  else
    echo "CHECKLIST state_dir_exists=0"
  fi
  if [[ -f "$env_file" ]]; then
    echo "CHECKLIST env_file_exists=1"
  else
    echo "CHECKLIST env_file_exists=0"
  fi

  cat <<EOF
SMOKE_STEP 1 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh daemon_status ${daemon_label}
SMOKE_STEP 2 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh watchdog_status ${watchdog_label}
SMOKE_STEP 3 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh github_health_check
SMOKE_STEP 4 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/run.sh status_snapshot
SMOKE_STEP 5 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/scripts/gh_app_auth_token.sh >/dev/null
EOF

  if [[ "$validation_failed" != "0" ]]; then
    echo "PREFLIGHT_READY=0"
    return 1
  fi

  echo "PREFLIGHT_READY=1"
}

case "$mode" in
  init)
    init_profile
    ;;
  install)
    install_profile
    ;;
  preflight)
    preflight_profile
    ;;
  bootstrap)
    init_profile
    install_profile
    preflight_profile
    ;;
  *)
    echo "Unknown mode: ${mode}" >&2
    usage
    exit 1
    ;;
esac
