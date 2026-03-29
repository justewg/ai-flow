#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/profile_init.sh <init|install|preflight|bootstrap|orchestrate> [options]

Modes:
  init        Создать env template, state-dir и расчетные service labels.
  install     Провалидировать env и установить daemon/watchdog для профиля.
  preflight   Вывести health/smoke checklist для профиля.
  bootstrap   Последовательно выполнить init -> install -> preflight.
  orchestrate Запустить финальный wizard pipeline: audit -> install -> smoke -> preflight.

Options:
  --profile <name>             Имя project profile (обязательно).
  --env-file <path>            Путь к project-scoped flow env-файлу.
  --state-dir <path>           Путь к profile state-dir.
  --project-profile <name>     Значение PROJECT_PROFILE (по умолчанию = profile).
  --daemon-label <label>       Launchd label daemon.
  --watchdog-label <label>     Launchd label watchdog.
  --daemon-interval <sec>      Интервал daemon (по умолчанию 45).
  --watchdog-interval <sec>    Интервал watchdog (по умолчанию 45).
  --skip-network               Только для orchestrate: пропустить network-checks в onboarding_audit.
  --force                      Перезаписать env template при init.
  --dry-run                    Ничего не менять, только показать действия.

Examples:
  .flow/shared/scripts/profile_init.sh init --profile acme
  .flow/shared/scripts/profile_init.sh install --profile acme
  .flow/shared/scripts/profile_init.sh preflight --profile acme
  .flow/shared/scripts/profile_init.sh bootstrap --profile acme --dry-run
  .flow/shared/scripts/profile_init.sh orchestrate --profile acme
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
skip_network="0"
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
    --skip-network)
      skip_network="1"
      shift
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
flow_state_root_dir="$(codex_resolve_flow_state_root_dir)"
ai_flow_state_root_dir="$(codex_resolve_ai_flow_state_root_dir)"
flow_env_file="$(codex_resolve_flow_env_file)"
flow_sample_env_file="$(codex_resolve_flow_sample_env_file)"
service_manager="$(codex_resolve_flow_service_manager)"
launchd_namespace="$(codex_resolve_flow_launchd_namespace)"
[[ -n "$project_profile" ]] || project_profile="$profile_slug"
[[ -n "$env_file" ]] || env_file="${flow_env_file}"
[[ -n "$state_dir" ]] || state_dir="${flow_state_root_dir}"
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
  local flow_logs_dir runtime_log_dir host_state_dir host_service_dir
  flow_logs_dir="$(resolve_flow_logs_dir_for_profile)"
  runtime_log_dir="$(resolve_runtime_log_dir_for_profile)"
  host_state_dir="$(resolve_ai_flow_state_dir_for_profile)"
  host_service_dir="$(resolve_host_service_dir_for_profile)"
  cat <<EOF
PROFILE=${profile}
PROFILE_SLUG=${profile_slug}
PROJECT_PROFILE=${project_profile}
ENV_FILE=${env_file}
SAMPLE_ENV_FILE=${flow_sample_env_file}
STATE_DIR=${state_dir}
HOST_STATE_DIR=${host_state_dir}
SERVICE_MANAGER=${service_manager}
SERVICE_UNIT_DIR=${host_service_dir}
LOG_DIR=${flow_logs_dir}
RUNTIME_LOG_DIR=${runtime_log_dir}
DAEMON_LABEL=${daemon_label}
DAEMON_INTERVAL=${daemon_interval}
WATCHDOG_LABEL=${watchdog_label}
WATCHDOG_INTERVAL=${watchdog_interval}
EOF
}

template_contents() {
  cat <<EOF
# Generated by .flow/shared/scripts/profile_init.sh for profile ${profile}
# Fill required values in .flow/config/flow.env before running install/preflight.
# Prefer interactive wizard for first setup or safe rerun:
#   .flow/shared/scripts/run.sh flow_configurator questionnaire --profile ${profile}

PROJECT_PROFILE=${project_profile}
GITHUB_REPO=
FLOW_BASE_BRANCH=main
FLOW_HEAD_BRANCH=development

# Runtime ownership contract:
# - authoritative: этот checkout имеет право запускать daemon/watchdog и брать задачи;
# - interactive-only: checkout остаётся только для ручной интерактивной работы, automation здесь не стартует.
# Для Linux/VPS authoritative runtime bootstrap обычно сам прописывает FLOW_AUTHORITATIVE_RUNTIME_ID.
# Если этот checkout не должен владеть automation-очередью, выставь:
#   FLOW_AUTOMATION_RUNTIME_ROLE=interactive-only
FLOW_AUTOMATION_RUNTIME_ROLE=authoritative
FLOW_AUTHORITATIVE_RUNTIME_ID=

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
OPS_BOT_REMOTE_STATE_DIR=<AI_FLOW_ROOT_DIR>/state/ops-bot/remote
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

# Optional host-level shared flow root/log/state layout.
# Defaults:
#   AI_FLOW_ROOT_DIR=<sites-root>/.ai-flow
#   FLOW_LOGS_DIR=<AI_FLOW_ROOT_DIR>/logs/<project-profile>
#   .flow/state -> <AI_FLOW_ROOT_DIR>/state/<project-profile>
#   .flow/launchd -> <AI_FLOW_ROOT_DIR>/launchd/<project-profile> (macOS launchd)
#   .flow/systemd -> <AI_FLOW_ROOT_DIR>/systemd/<project-profile> (Linux systemd)
# Uncomment only if you want explicit non-default paths.
# AI_FLOW_ROOT_DIR=
# FLOW_LOGS_DIR=

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

resolve_flow_logs_dir_for_profile() {
  local configured_logs_dir ai_flow_logs_root_dir
  configured_logs_dir="$(codex_read_key_from_env_file "$env_file" "FLOW_LOGS_DIR" || true)"
  if [[ -n "$configured_logs_dir" ]]; then
    printf '%s' "$configured_logs_dir"
    return 0
  fi
  ai_flow_logs_root_dir="$(codex_resolve_ai_flow_logs_root_dir)"
  printf '%s/%s' "$ai_flow_logs_root_dir" "$(codex_slugify_value "$project_profile")"
}

resolve_runtime_log_dir_for_profile() {
  local flow_logs_dir
  flow_logs_dir="$(resolve_flow_logs_dir_for_profile)"
  printf '%s/runtime' "$flow_logs_dir"
}

resolve_ai_flow_state_dir_for_profile() {
  local configured_ai_flow_root state_root
  configured_ai_flow_root="$(codex_read_key_from_env_file "$env_file" "AI_FLOW_ROOT_DIR" || true)"
  if [[ -n "$configured_ai_flow_root" ]]; then
    state_root="${configured_ai_flow_root}/state"
  else
    state_root="$ai_flow_state_root_dir"
  fi
  printf '%s/%s' "$state_root" "$(codex_slugify_value "$project_profile")"
}

resolve_ai_flow_launchd_dir_for_profile() {
  local configured_ai_flow_root launchd_root
  configured_ai_flow_root="$(codex_read_key_from_env_file "$env_file" "AI_FLOW_ROOT_DIR" || true)"
  if [[ -n "$configured_ai_flow_root" ]]; then
    launchd_root="${configured_ai_flow_root}/launchd"
  else
    launchd_root="$(codex_resolve_ai_flow_launchd_root_dir)"
  fi
  printf '%s/%s' "$launchd_root" "$(codex_slugify_value "$project_profile")"
}

resolve_ai_flow_systemd_dir_for_profile() {
  local configured_ai_flow_root systemd_root
  configured_ai_flow_root="$(codex_read_key_from_env_file "$env_file" "AI_FLOW_ROOT_DIR" || true)"
  if [[ -n "$configured_ai_flow_root" ]]; then
    systemd_root="${configured_ai_flow_root}/systemd"
  else
    systemd_root="$(codex_resolve_ai_flow_systemd_root_dir)"
  fi
  printf '%s/%s' "$systemd_root" "$(codex_slugify_value "$project_profile")"
}

resolve_host_service_dir_for_profile() {
  case "$service_manager" in
    launchd) resolve_ai_flow_launchd_dir_for_profile ;;
    systemd) resolve_ai_flow_systemd_dir_for_profile ;;
    *)
      echo "Unsupported FLOW_SERVICE_MANAGER=${service_manager}" >&2
      return 1
      ;;
  esac
}

ensure_state_symlink_target() {
  local state_link_path="$1"
  local host_state_dir_path="$2"

  ensure_dir "$host_state_dir_path"

  if [[ "$state_link_path" == "$host_state_dir_path" ]]; then
    return 0
  fi

  ensure_dir "$(dirname "$state_link_path")"

  if [[ -L "$state_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$host_state_dir_path" "$state_link_path"
      return 0
    fi
    ln -sfn "$host_state_dir_path" "$state_link_path"
    return 0
  fi

  if [[ -e "$state_link_path" && ! -L "$state_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN preserve-existing-state-dir %s\n' "$state_link_path"
      return 0
    fi
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN ln -s %s %s\n' "$host_state_dir_path" "$state_link_path"
    return 0
  fi
  ln -s "$host_state_dir_path" "$state_link_path"
}

ensure_launchd_symlink_target() {
  local launchd_link_path="$1"
  local host_launchd_dir_path="$2"

  ensure_dir "$host_launchd_dir_path"

  if [[ "$launchd_link_path" == "$host_launchd_dir_path" ]]; then
    return 0
  fi

  ensure_dir "$(dirname "$launchd_link_path")"

  if [[ -L "$launchd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$host_launchd_dir_path" "$launchd_link_path"
      return 0
    fi
    ln -sfn "$host_launchd_dir_path" "$launchd_link_path"
    return 0
  fi

  if [[ -d "$launchd_link_path" && ! -L "$launchd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN preserve-existing-launchd-dir %s\n' "$launchd_link_path"
      return 0
    fi
    return 0
  fi

  if [[ -e "$launchd_link_path" && ! -L "$launchd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN preserve-existing-launchd-path %s\n' "$launchd_link_path"
      return 0
    fi
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN ln -s %s %s\n' "$host_launchd_dir_path" "$launchd_link_path"
    return 0
  fi
  ln -s "$host_launchd_dir_path" "$launchd_link_path"
}

ensure_systemd_symlink_target() {
  local systemd_link_path="$1"
  local host_systemd_dir_path="$2"

  ensure_dir "$host_systemd_dir_path"

  if [[ "$systemd_link_path" == "$host_systemd_dir_path" ]]; then
    return 0
  fi

  ensure_dir "$(dirname "$systemd_link_path")"

  if [[ -L "$systemd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$host_systemd_dir_path" "$systemd_link_path"
      return 0
    fi
    ln -sfn "$host_systemd_dir_path" "$systemd_link_path"
    return 0
  fi

  if [[ -d "$systemd_link_path" && ! -L "$systemd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN preserve-existing-systemd-dir %s\n' "$systemd_link_path"
      return 0
    fi
    return 0
  fi

  if [[ -e "$systemd_link_path" && ! -L "$systemd_link_path" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN preserve-existing-systemd-path %s\n' "$systemd_link_path"
      return 0
    fi
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN ln -s %s %s\n' "$host_systemd_dir_path" "$systemd_link_path"
    return 0
  fi
  ln -s "$host_systemd_dir_path" "$systemd_link_path"
}

ensure_runtime_log_layout() {
  local runtime_log_dir_path="$1"
  local log_name log_path alias_name alias_path target_name target_path
  local -a canonical_logs=(
    daemon.log
    executor.log
    watchdog.log
    graphql_rate_stats.log
  )
  local -a alias_logs=(
    "launchd.out.log:daemon.log"
    "launchd.err.log:daemon.log"
    "watchdog.launchd.out.log:watchdog.log"
    "watchdog.launchd.err.log:watchdog.log"
  )

  ensure_dir "$runtime_log_dir_path"

  for log_name in "${canonical_logs[@]}"; do
    log_path="${runtime_log_dir_path}/${log_name}"
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN touch %s\n' "$log_path"
      continue
    fi
    [[ -e "$log_path" ]] || : > "$log_path"
  done

  for alias_name in "${alias_logs[@]}"; do
    alias_path="${runtime_log_dir_path}/${alias_name%%:*}"
    target_name="${alias_name#*:}"
    target_path="${runtime_log_dir_path}/${target_name}"

    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$target_path" "$alias_path"
      continue
    fi

    if [[ -L "$alias_path" ]]; then
      ln -sfn "$target_path" "$alias_path"
      continue
    fi

    if [[ -f "$alias_path" && "$alias_path" != "$target_path" ]]; then
      if [[ -s "$alias_path" ]]; then
        cat "$alias_path" >> "$target_path"
      fi
      rm -f "$alias_path"
    fi

    ln -sfn "$target_path" "$alias_path"
  done
}

ensure_legacy_state_log_links() {
  local state_dir_path="$1"
  local runtime_log_dir_path="$2"
  local log_name state_link target_link
  local -a log_names=(
    daemon.log
    executor.log
    watchdog.log
    graphql_rate_stats.log
    launchd.out.log
    launchd.err.log
    watchdog.launchd.out.log
    watchdog.launchd.err.log
  )

  ensure_runtime_log_layout "$runtime_log_dir_path"

  for log_name in "${log_names[@]}"; do
    state_link="${state_dir_path}/${log_name}"
    target_link="${runtime_log_dir_path}/${log_name}"
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$target_link" "$state_link"
      continue
    fi
    ln -sfn "$target_link" "$state_link"
  done
}

ensure_state_namespace_layout() {
  local state_dir_path="$1"
  local namespace_dir link_name target_path source_path seed_path
  local -a namespace_dirs=(
    daemon
    watchdog
    executor
    project
    github
    ops
    inputs
    queue
    tmp
  )
  local -a file_links=(
    "inputs:commit_message.txt"
    "inputs:pr_body.txt"
    "inputs:pr_number.txt"
    "inputs:pr_title.txt"
    "inputs:project_task_id.txt"
    "inputs:stage_paths.txt"
    "daemon:daemon_active_issue_number.txt"
    "daemon:daemon_active_item_id.txt"
    "daemon:daemon_active_task.txt"
    "daemon:daemon_github_runtime_notify_mode.txt"
    "daemon:daemon_last_claim_utc.txt"
    "daemon:daemon_notify_last_epoch.txt"
    "daemon:daemon_notify_last_signature.txt"
    "daemon:daemon_notify_mode.txt"
    "daemon:daemon_review_issue_number.txt"
    "daemon:daemon_review_item_id.txt"
    "daemon:daemon_review_pr_number.txt"
    "daemon:daemon_review_task_id.txt"
    "daemon:daemon_state.txt"
    "daemon:daemon_state_detail.txt"
    "daemon:daemon_user_reply.txt"
    "daemon:daemon_user_reply_at_utc.txt"
    "daemon:daemon_user_reply_author.txt"
    "daemon:daemon_user_reply_comment_id.txt"
    "daemon:daemon_user_reply_comment_url.txt"
    "daemon:daemon_user_reply_issue_number.txt"
    "daemon:daemon_user_reply_task_id.txt"
    "daemon:daemon_waiting_comment_url.txt"
    "daemon:daemon_waiting_issue_number.txt"
    "daemon:daemon_waiting_kind.txt"
    "daemon:daemon_waiting_pending_post.txt"
    "daemon:daemon_waiting_question_comment_id.txt"
    "daemon:daemon_waiting_since_utc.txt"
    "daemon:daemon_waiting_task_id.txt"
    "watchdog:watchdog_last_action.txt"
    "watchdog:watchdog_last_action_epoch.txt"
    "watchdog:watchdog_state.txt"
    "watchdog:watchdog_state_detail.txt"
    "executor:executor_done_wait_notified_task.txt"
    "executor:executor_failure_notified_task.txt"
    "executor:executor_heartbeat_epoch.txt"
    "executor:executor_heartbeat_pid.txt"
    "executor:executor_heartbeat_utc.txt"
    "executor:executor_issue_number.txt"
    "executor:executor_last_exit_code.txt"
    "executor:executor_review_handoff_reason.txt"
    "executor:executor_last_finished_utc.txt"
    "executor:executor_last_message.txt"
    "executor:executor_last_start_epoch.txt"
    "executor:executor_last_started_utc.txt"
    "executor:executor_pid.txt"
    "executor:executor_prompt.txt"
    "executor:executor_state.txt"
    "executor:executor_task_id.txt"
    "project:project_status_runtime_queue.json"
    "project:project_status_runtime_queue.md"
    "github:graphql_rate_last_success_utc.txt"
    "github:graphql_rate_window_requests.txt"
    "github:graphql_rate_window_start_epoch.txt"
    "github:graphql_rate_window_start_utc.txt"
    "github:graphql_rate_window_state.txt"
    "ops:ops_remote_push_response.json"
    "ops:ops_remote_summary_last_push_epoch.txt"
    "ops:ops_remote_summary_push_response.json"
  )
  local -a dir_links=(
    "outbox:queue/outbox"
    "outbox_failed:queue/outbox_failed"
    "outbox_payloads:queue/outbox_payloads"
    "daemon.lock:daemon/lock"
    "watchdog.lock:watchdog/lock"
  )

  for namespace_dir in "${namespace_dirs[@]}"; do
    ensure_dir "${state_dir_path}/${namespace_dir}"
  done
  ensure_dir "${state_dir_path}/queue/outbox"
  ensure_dir "${state_dir_path}/queue/outbox_failed"
  ensure_dir "${state_dir_path}/queue/outbox_payloads"

  for source_path in "${file_links[@]}"; do
    namespace_dir="${source_path%%:*}"
    link_name="${source_path#*:}"
    target_path="${state_dir_path}/${namespace_dir}/${link_name}"
    source_path="${state_dir_path}/${link_name}"

    if [[ -e "$source_path" && ! -L "$source_path" && ! -e "$target_path" ]]; then
      if [[ "$dry_run" == "1" ]]; then
        printf 'DRY_RUN mv %s %s\n' "$source_path" "$target_path"
      else
        mv "$source_path" "$target_path"
      fi
    fi

    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$target_path" "$source_path"
    else
      ln -sfn "$target_path" "$source_path"
    fi
  done

  local -a seed_files=(
    "project/project_status_runtime_queue.json"
    "project/project_status_runtime_queue.md"
  )

  for seed_path in "${seed_files[@]}"; do
    target_path="${state_dir_path}/${seed_path}"
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN touch %s\n' "$target_path"
      continue
    fi
    [[ -e "$target_path" ]] || : > "$target_path"
  done

  for source_path in "${dir_links[@]}"; do
    link_name="${source_path%%:*}"
    target_path="${state_dir_path}/${source_path#*:}"
    source_path="${state_dir_path}/${link_name}"

    if [[ -d "$source_path" && ! -L "$source_path" ]]; then
      if [[ "$source_path" != "$target_path" ]]; then
        ensure_dir "$target_path"
        if [[ "$dry_run" == "1" ]]; then
          printf 'DRY_RUN move-dir-contents %s -> %s\n' "$source_path" "$target_path"
          printf 'DRY_RUN rmdir %s\n' "$source_path"
        else
          find "$source_path" -mindepth 1 -maxdepth 1 -exec mv {} "$target_path"/ \;
          rmdir "$source_path" 2>/dev/null || true
        fi
      fi
    elif [[ -e "$source_path" && ! -L "$source_path" && ! -e "$target_path" ]]; then
      if [[ "$dry_run" == "1" ]]; then
        printf 'DRY_RUN mv %s %s\n' "$source_path" "$target_path"
      else
        mv "$source_path" "$target_path"
      fi
    fi

    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN ln -sfn %s %s\n' "$target_path" "$source_path"
    else
      ln -sfn "$target_path" "$source_path"
    fi
  done
}

migrate_state_temp_artifacts() {
  local state_dir_path="$1"
  local tmp_dir="${state_dir_path}/tmp"
  local pattern file_path target_path
  local -a patterns=(
    "daemon_auth.*"
    "watchdog_auth.*"
    "gh_retry_err.*"
    "dependency_cache.*"
    "dependency_block_gh_err.*"
    "dependency_block_body.*"
    "daemon_runtime_notify.*"
    "daemon_notify.*"
    "executor_failed.*"
    "executor_done_wait.*"
    "answer_body.*"
    "ack_body.*"
    "task_ask_gh_err.*"
    "question_body.*"
    "status_runtime.*"
    "seed_gh_err.*"
    "seed_plan.*"
    "seed_issue_body.*"
    "app_deps_*"
    "issue285.*"
    "final_comment_gh_err.*"
    "in_review_comment.*"
    "review_anchor_recover.*"
    "outbox_gh_err.*"
    "outbox_item.*"
    "executor_log_slice.*"
  )

  ensure_dir "$tmp_dir"

  for pattern in "${patterns[@]}"; do
    for file_path in "${state_dir_path}"/${pattern}; do
      [[ -e "$file_path" ]] || continue
      [[ -L "$file_path" ]] && continue
      target_path="${tmp_dir}/$(basename "$file_path")"
      [[ "$file_path" == "$target_path" ]] && continue
      if [[ -e "$target_path" ]]; then
        continue
      fi
      if [[ "$dry_run" == "1" ]]; then
        printf 'DRY_RUN mv %s %s\n' "$file_path" "$target_path"
      else
        mv "$file_path" "$target_path"
      fi
    done
  done
}

init_profile() {
  local host_state_dir host_service_dir
  emit_profile_summary
  ensure_dir "$(dirname "$env_file")"
  host_state_dir="$(resolve_ai_flow_state_dir_for_profile)"
  host_service_dir="$(resolve_host_service_dir_for_profile)"
  ensure_state_symlink_target "$state_dir" "$host_state_dir"
  case "$service_manager" in
    launchd) ensure_launchd_symlink_target "${ROOT_DIR}/.flow/launchd" "$host_service_dir" ;;
    systemd) ensure_systemd_symlink_target "${ROOT_DIR}/.flow/systemd" "$host_service_dir" ;;
  esac
  ensure_dir "$host_state_dir"
  ensure_state_namespace_layout "$host_state_dir"
  migrate_state_temp_artifacts "$host_state_dir"
  ensure_legacy_state_log_links "$host_state_dir" "$(resolve_runtime_log_dir_for_profile)"

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

run_logged_command() {
  local output_file="$1"
  shift
  if "$@" >"$output_file" 2>&1; then
    cat "$output_file"
    return 0
  fi
  local rc=$?
  cat "$output_file"
  return "$rc"
}

first_status_token() {
  local summary="$1"
  summary="${summary#"${summary%%[![:space:]]*}"}"
  printf '%s' "${summary%% *}"
}

runtime_mode_value() {
  codex_resolve_config_value "FLOW_HOST_RUNTIME_MODE" ""
}

runtime_ownership_state_value() {
  codex_resolve_flow_runtime_ownership_state
}

runtime_ownership_summary() {
  local ownership_state runtime_role runtime_instance_id authoritative_runtime_id
  ownership_state="$(runtime_ownership_state_value)"
  runtime_role="$(codex_resolve_flow_automation_runtime_role)"
  runtime_instance_id="$(codex_resolve_flow_runtime_instance_id)"
  authoritative_runtime_id="$(codex_resolve_flow_authoritative_runtime_id)"

  printf '%s role=%s instance=%s' "$ownership_state" "$runtime_role" "$runtime_instance_id"
  if [[ -n "$authoritative_runtime_id" ]]; then
    printf ' authoritative=%s' "$authoritative_runtime_id"
  fi
}

status_snapshot_summary() {
  local component="$1"
  local snapshot_json snapshot_overall snapshot_headline component_state
  if ! snapshot_json="$("${CODEX_SHARED_SCRIPTS_DIR}/status_snapshot.sh" 2>&1)"; then
    printf 'ERROR status_snapshot_failed %s' "$(printf '%s' "$snapshot_json" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
    return 1
  fi

  if ! jq -e . >/dev/null 2>&1 <<< "$snapshot_json"; then
    printf 'ERROR invalid_status_snapshot_json'
    return 1
  fi

  snapshot_overall="$(jq -r '.overall_status // "UNKNOWN"' <<< "$snapshot_json")"
  snapshot_headline="$(jq -r '.headline // ""' <<< "$snapshot_json")"
  case "$component" in
    daemon)
      component_state="$(jq -r '.daemon.state // "UNKNOWN"' <<< "$snapshot_json")"
      ;;
    watchdog)
      component_state="$(jq -r '.watchdog.state // "UNKNOWN"' <<< "$snapshot_json")"
      ;;
    *)
      printf 'ERROR unknown_snapshot_component=%s' "$component"
      return 1
      ;;
  esac

  if [[ -z "$component_state" || "$component_state" == "UNKNOWN" ]]; then
    printf 'ERROR linux-docker-hosted SNAPSHOT_OVERALL=%s %s_STATE=%s HEADLINE=%s' \
      "$snapshot_overall" "$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')" "$component_state" "$snapshot_headline"
    return 1
  fi

  printf 'RUNNING linux-docker-hosted SNAPSHOT_OVERALL=%s %s_STATE=%s HEADLINE=%s' \
    "$snapshot_overall" "$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')" "$component_state" "$snapshot_headline"
}

runtime_status_summary() {
  local component="$1"
  local label="$2"
  local script_path="$3"
  local runtime_mode
  runtime_mode="$(runtime_mode_value)"
  if [[ "$runtime_mode" == "linux-docker-hosted" ]]; then
    status_snapshot_summary "$component"
    return $?
  fi
  status_summary "$label" "$script_path"
}

emit_prefixed_entries() {
  local output_file="$1"
  local marker="$2"
  local prefix="$3"
  local line payload
  while IFS= read -r line; do
    case "$line" in
      *"${marker} "*)
        payload="${line#*"${marker} "}"
        printf '%s %s\n' "$prefix" "$payload"
        ;;
    esac
  done < "$output_file"
}

install_profile() {
  local ownership_state ownership_summary
  emit_profile_summary
  ownership_state="$(runtime_ownership_state_value)"
  ownership_summary="$(runtime_ownership_summary)"
  echo "CHECKLIST runtime_ownership=${ownership_summary}"
  if [[ "$dry_run" == "1" && ! -f "$env_file" ]]; then
    echo "CHECK_WARN ENV_FILE=missing:${env_file}"
    ensure_dir "$state_dir"
    echo "INSTALL_STEP daemon_install=DRY_RUN"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "${CODEX_SHARED_SCRIPTS_DIR}/daemon_install.sh" "$daemon_label" "$daemon_interval"
    echo "INSTALL_STEP watchdog_install=DRY_RUN"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s WATCHDOG_DAEMON_LABEL=%s WATCHDOG_DAEMON_INTERVAL_SEC=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "$daemon_label" "$daemon_interval" "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_install.sh" "$watchdog_label" "$watchdog_interval"
    echo "INSTALL_DRY_RUN_ONLY=1"
    return 0
  fi

  validate_required_env
  if [[ "$validation_failed" != "0" ]]; then
    echo "INSTALL_ABORTED=1"
    return 1
  fi

  case "$ownership_state" in
    INTERACTIVE_ONLY)
      echo "INSTALL_SKIP_RUNTIME_OWNERSHIP=INTERACTIVE_ONLY"
      echo "INSTALL_RUNTIME_OWNERSHIP=${ownership_summary}"
      return 0
      ;;
    OWNER_MISMATCH)
      echo "INSTALL_SKIP_RUNTIME_OWNERSHIP=OWNER_MISMATCH"
      echo "INSTALL_RUNTIME_OWNERSHIP=${ownership_summary}"
      return 0
      ;;
  esac

  local host_state_dir host_service_dir
  host_state_dir="$(resolve_ai_flow_state_dir_for_profile)"
  host_service_dir="$(resolve_host_service_dir_for_profile)"
  ensure_state_symlink_target "$state_dir" "$host_state_dir"
  case "$service_manager" in
    launchd) ensure_launchd_symlink_target "${ROOT_DIR}/.flow/launchd" "$host_service_dir" ;;
    systemd) ensure_systemd_symlink_target "${ROOT_DIR}/.flow/systemd" "$host_service_dir" ;;
  esac
  ensure_dir "$host_state_dir"
  ensure_state_namespace_layout "$host_state_dir"
  migrate_state_temp_artifacts "$host_state_dir"
  ensure_legacy_state_log_links "$host_state_dir" "$(resolve_runtime_log_dir_for_profile)"

  local daemon_cmd=("${CODEX_SHARED_SCRIPTS_DIR}/daemon_install.sh" "$daemon_label" "$daemon_interval")
  local watchdog_cmd=("${CODEX_SHARED_SCRIPTS_DIR}/watchdog_install.sh" "$watchdog_label" "$watchdog_interval")

  if [[ "$dry_run" == "1" ]]; then
    echo "INSTALL_STEP daemon_install=DRY_RUN"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "${daemon_cmd[0]}" "${daemon_cmd[1]}" "${daemon_cmd[2]}"
    echo "INSTALL_STEP watchdog_install=DRY_RUN"
    printf 'DRY_RUN env DAEMON_GH_ENV_FILE=%s CODEX_STATE_DIR=%s FLOW_STATE_DIR=%s WATCHDOG_DAEMON_LABEL=%s WATCHDOG_DAEMON_INTERVAL_SEC=%s %s %s %s\n' \
      "$env_file" "$state_dir" "$state_dir" "$daemon_label" "$daemon_interval" "${watchdog_cmd[0]}" "${watchdog_cmd[1]}" "${watchdog_cmd[2]}"
    return 0
  fi

  echo "INSTALL_STEP daemon_install=STARTED"
  DAEMON_GH_ENV_FILE="$env_file" CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" \
    "${daemon_cmd[@]}"
  echo "INSTALL_STEP daemon_install=COMPLETED"
  echo "INSTALL_STEP watchdog_install=STARTED"
  DAEMON_GH_ENV_FILE="$env_file" CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" \
    WATCHDOG_DAEMON_LABEL="$daemon_label" WATCHDOG_DAEMON_INTERVAL_SEC="$daemon_interval" \
    "${watchdog_cmd[@]}"
  echo "INSTALL_STEP watchdog_install=COMPLETED"
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
SMOKE_STEP 1 .flow/shared/scripts/run.sh profile_init init --profile ${profile} --env-file ${env_file} --state-dir ${state_dir}
SMOKE_STEP 2 fill required env in ${env_file}
SMOKE_STEP 3 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh profile_init install --profile ${profile}
SMOKE_STEP 4 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh github_health_check
SMOKE_STEP 5 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh status_snapshot
EOF
    echo "PREFLIGHT_READY=0"
    return 0
  fi

  validate_required_env || true

  local daemon_status watchdog_status daemon_status_head watchdog_status_head runtime_ready runtime_mode ownership_state ownership_summary
  local linux_host_preflight_out linux_host_preflight_rc
  local state_dir_check_path
  runtime_mode="$(runtime_mode_value)"
  ownership_state="$(runtime_ownership_state_value)"
  ownership_summary="$(runtime_ownership_summary)"
  daemon_status="$(runtime_status_summary daemon "$daemon_label" "${CODEX_SHARED_SCRIPTS_DIR}/daemon_status.sh")"
  watchdog_status="$(runtime_status_summary watchdog "$watchdog_label" "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_status.sh")"
  daemon_status_head="$(first_status_token "$daemon_status")"
  watchdog_status_head="$(first_status_token "$watchdog_status")"
  runtime_ready="1"
  state_dir_check_path="$state_dir"
  if [[ "$runtime_mode" == "linux-docker-hosted" ]]; then
    state_dir_check_path="$(resolve_ai_flow_state_dir_for_profile)"
  fi

  echo "CHECKLIST runtime_ownership=${ownership_summary}"
  echo "CHECKLIST daemon_status=${daemon_status}"
  echo "CHECKLIST watchdog_status=${watchdog_status}"
  if [[ -d "$state_dir_check_path" ]]; then
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
SMOKE_STEP 1 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh daemon_status ${daemon_label}
SMOKE_STEP 2 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh watchdog_status ${watchdog_label}
SMOKE_STEP 3 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh github_health_check
SMOKE_STEP 4 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh status_snapshot
SMOKE_STEP 5 env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/gh_app_auth_token.sh >/dev/null
EOF

  linux_host_preflight_out="$("${CODEX_SHARED_SCRIPTS_DIR}/linux_host_codex_preflight.sh" 2>&1 || true)"
  linux_host_preflight_rc=0
  if [[ -n "$linux_host_preflight_out" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line"
    done <<< "$linux_host_preflight_out"
  fi
  if printf '%s\n' "$linux_host_preflight_out" | grep -q '^CHECK_FAIL '; then
    linux_host_preflight_rc=1
  fi

  case "$ownership_state" in
    INTERACTIVE_ONLY|OWNER_MISMATCH)
      report_ok "RUNTIME_OWNERSHIP" "${ownership_summary}"
      report_ok "DAEMON_STATUS" "${daemon_status}"
      report_ok "WATCHDOG_STATUS" "${watchdog_status}"
      ;;
    *)
      report_ok "RUNTIME_OWNERSHIP" "${ownership_summary}"
      if [[ "$daemon_status_head" != "RUNNING" ]]; then
        report_fail "DAEMON_STATUS" "${daemon_status}"
        runtime_ready="0"
      else
        report_ok "DAEMON_STATUS" "${daemon_status}"
      fi

      if [[ "$watchdog_status_head" != "RUNNING" ]]; then
        report_fail "WATCHDOG_STATUS" "${watchdog_status}"
        runtime_ready="0"
      else
        report_ok "WATCHDOG_STATUS" "${watchdog_status}"
      fi
      ;;
  esac

  if [[ "$linux_host_preflight_rc" != "0" ]]; then
    runtime_ready="0"
  fi

  if [[ "$validation_failed" != "0" || "$runtime_ready" != "1" ]]; then
    echo "PREFLIGHT_READY=0"
    return 1
  fi

  echo "PREFLIGHT_READY=1"
}

orchestrate_profile() {
  local tmp_root report_file retry_hint rollback_hint
  local audit_output install_output health_output snapshot_output preflight_output
  local audit_rc install_rc health_rc snapshot_rc preflight_rc
  local audit_ok audit_warn audit_fail audit_action audit_ready
  local daemon_status daemon_status_head watchdog_status watchdog_status_head
  local github_health snapshot_overall snapshot_headline preflight_ready
  local orchestrate_result audit_summary_line step_count completed_steps
  local manual_action_count blocker_count

  tmp_root="$(codex_resolve_flow_tmp_dir)/wizard"
  report_file="${tmp_root}/profile-init-orchestrate-${profile_slug}.report.txt"
  retry_hint="env DAEMON_GH_ENV_FILE=${env_file} CODEX_STATE_DIR=${state_dir} FLOW_STATE_DIR=${state_dir} .flow/shared/scripts/run.sh profile_init orchestrate --profile ${profile}"
  rollback_hint=".flow/shared/scripts/run.sh watchdog_uninstall ${watchdog_label} && .flow/shared/scripts/run.sh daemon_uninstall ${daemon_label}"

  audit_output="$(mktemp)"
  install_output="$(mktemp)"
  health_output="$(mktemp)"
  snapshot_output="$(mktemp)"
  preflight_output="$(mktemp)"

  echo "ORCHESTRATION_STEP audit=STARTED"
  if run_logged_command "$audit_output" \
    "${CODEX_SHARED_SCRIPTS_DIR}/onboarding_audit.sh" \
    --profile "$profile" \
    --env-file "$env_file" \
    --state-dir "$state_dir" \
    $([[ "$skip_network" == "1" ]] && printf '%s' "--skip-network"); then
    audit_rc=0
  else
    audit_rc=$?
  fi
  echo "ORCHESTRATION_STEP audit=$([[ "$audit_rc" -eq 0 ]] && printf '%s' COMPLETED || printf '%s' FAILED)"

  audit_summary_line="$(grep -E '^SUMMARY ok=[0-9]+ warn=[0-9]+ fail=[0-9]+ action=[0-9]+$' "$audit_output" | tail -n1 || true)"
  audit_ok="$(printf '%s' "$audit_summary_line" | sed -nE 's/^SUMMARY ok=([0-9]+) warn=([0-9]+) fail=([0-9]+) action=([0-9]+)$/\1/p')"
  audit_warn="$(printf '%s' "$audit_summary_line" | sed -nE 's/^SUMMARY ok=([0-9]+) warn=([0-9]+) fail=([0-9]+) action=([0-9]+)$/\2/p')"
  audit_fail="$(printf '%s' "$audit_summary_line" | sed -nE 's/^SUMMARY ok=([0-9]+) warn=([0-9]+) fail=([0-9]+) action=([0-9]+)$/\3/p')"
  audit_action="$(printf '%s' "$audit_summary_line" | sed -nE 's/^SUMMARY ok=([0-9]+) warn=([0-9]+) fail=([0-9]+) action=([0-9]+)$/\4/p')"
  audit_ready="$(grep -E '^READY_FOR_AUTOMATION=' "$audit_output" | tail -n1 | cut -d'=' -f2 || true)"
  [[ -n "$audit_ok" ]] || audit_ok="0"
  [[ -n "$audit_warn" ]] || audit_warn="0"
  [[ -n "$audit_fail" ]] || audit_fail="0"
  [[ -n "$audit_action" ]] || audit_action="0"
  [[ -n "$audit_ready" ]] || audit_ready="0"

  echo "AUDIT_SUMMARY ok=${audit_ok} warn=${audit_warn} fail=${audit_fail} action=${audit_action} ready=${audit_ready}"
  emit_prefixed_entries "$audit_output" "CHECK_OK" "AUDIT_READY"
  emit_prefixed_entries "$audit_output" "CHECK_WARN" "AUDIT_WARN"
  emit_prefixed_entries "$audit_output" "CHECK_FAIL" "AUDIT_BLOCKER"
  emit_prefixed_entries "$audit_output" "ACTION" "AUDIT_ACTION"

  if [[ "$audit_rc" -ne 0 || "$audit_ready" != "1" ]]; then
    daemon_status="$(runtime_status_summary daemon "$daemon_label" "${CODEX_SHARED_SCRIPTS_DIR}/daemon_status.sh")"
    watchdog_status="$(runtime_status_summary watchdog "$watchdog_label" "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_status.sh")"
    orchestrate_result="blocked"
    manual_action_count="$(grep -c 'ACTION ' "$audit_output" || true)"
    blocker_count="$(grep -c 'CHECK_FAIL ' "$audit_output" || true)"
    echo "FINAL_SUMMARY result=${orchestrate_result}"
    echo "FINAL_SUMMARY daemon_status=${daemon_status}"
    echo "FINAL_SUMMARY watchdog_status=${watchdog_status}"
    echo "FINAL_SUMMARY blocked_by_audit=${blocker_count}"
    echo "FINAL_SUMMARY remaining_manual_actions=${manual_action_count}"
    echo "RECOVERY_RETRY ${retry_hint}"
    echo "RECOVERY_ROLLBACK ${rollback_hint}"
    if [[ "$dry_run" != "1" ]]; then
      mkdir -p "$tmp_root"
      {
        echo "PROFILE=${profile}"
        echo "RESULT=${orchestrate_result}"
        echo "AUDIT_OK=${audit_ok}"
        echo "AUDIT_WARN=${audit_warn}"
        echo "AUDIT_FAIL=${audit_fail}"
        echo "AUDIT_ACTION=${audit_action}"
        echo "DAEMON_STATUS=${daemon_status}"
        echo "WATCHDOG_STATUS=${watchdog_status}"
        echo "RETRY_HINT=${retry_hint}"
        echo "ROLLBACK_HINT=${rollback_hint}"
        emit_prefixed_entries "$audit_output" "CHECK_FAIL" "BLOCKER"
        emit_prefixed_entries "$audit_output" "ACTION" "MANUAL_ACTION"
      } >"$report_file"
      echo "ORCHESTRATION_REPORT=${report_file}"
    fi
    rm -f "$audit_output" "$install_output" "$health_output" "$snapshot_output" "$preflight_output"
    return 1
  fi

  echo "ORCHESTRATION_STEP install=STARTED"
  if install_profile >"$install_output" 2>&1; then
    install_rc=0
  else
    install_rc=$?
  fi
  cat "$install_output"
  echo "ORCHESTRATION_STEP install=$([[ "$install_rc" -eq 0 ]] && printf '%s' COMPLETED || printf '%s' FAILED)"

  daemon_status="$(runtime_status_summary daemon "$daemon_label" "${CODEX_SHARED_SCRIPTS_DIR}/daemon_status.sh")"
  watchdog_status="$(runtime_status_summary watchdog "$watchdog_label" "${CODEX_SHARED_SCRIPTS_DIR}/watchdog_status.sh")"
  daemon_status_head="$(first_status_token "$daemon_status")"
  watchdog_status_head="$(first_status_token "$watchdog_status")"

  if [[ "$dry_run" == "1" ]]; then
    health_rc=0
    snapshot_rc=0
    preflight_rc=0
    github_health="SKIPPED_DRY_RUN"
    snapshot_overall="SKIPPED_DRY_RUN"
    snapshot_headline="dry-run"
    preflight_ready="0"
    echo "ORCHESTRATION_STEP github_health_check=SKIPPED_DRY_RUN"
    echo "ORCHESTRATION_STEP status_snapshot=SKIPPED_DRY_RUN"
    echo "ORCHESTRATION_STEP preflight=SKIPPED_DRY_RUN"
    if preflight_profile >"$preflight_output" 2>&1; then
      :
    else
      :
    fi
    cat "$preflight_output"
  else
    echo "ORCHESTRATION_STEP github_health_check=STARTED"
    if run_logged_command "$health_output" env \
      DAEMON_GH_ENV_FILE="$env_file" \
      CODEX_STATE_DIR="$state_dir" \
      FLOW_STATE_DIR="$state_dir" \
      "${CODEX_SHARED_SCRIPTS_DIR}/github_health_check.sh"; then
      health_rc=0
    else
      health_rc=$?
    fi
    github_health="$(grep -E '^GITHUB_HEALTHY=' "$health_output" | tail -n1 | cut -d'=' -f2 || true)"
    [[ -n "$github_health" ]] || github_health="0"
    echo "ORCHESTRATION_STEP github_health_check=$([[ "$health_rc" -eq 0 ]] && printf '%s' COMPLETED || printf '%s' FAILED)"

    echo "ORCHESTRATION_STEP status_snapshot=STARTED"
    if run_logged_command "$snapshot_output" env \
      DAEMON_GH_ENV_FILE="$env_file" \
      CODEX_STATE_DIR="$state_dir" \
      FLOW_STATE_DIR="$state_dir" \
      "${CODEX_SHARED_SCRIPTS_DIR}/status_snapshot.sh"; then
      snapshot_rc=0
    else
      snapshot_rc=$?
    fi
    if jq -e . >/dev/null 2>&1 <"$snapshot_output"; then
      snapshot_overall="$(jq -r '.overall_status // "UNKNOWN"' "$snapshot_output")"
      snapshot_headline="$(jq -r '.headline // ""' "$snapshot_output")"
    else
      snapshot_overall="INVALID_JSON"
      snapshot_headline=""
    fi
    echo "ORCHESTRATION_STEP status_snapshot=$([[ "$snapshot_rc" -eq 0 ]] && printf '%s' COMPLETED || printf '%s' FAILED)"

    echo "ORCHESTRATION_STEP preflight=STARTED"
    if preflight_profile >"$preflight_output" 2>&1; then
      preflight_rc=0
    else
      preflight_rc=$?
    fi
    cat "$preflight_output"
    preflight_ready="$(grep -E '^PREFLIGHT_READY=' "$preflight_output" | tail -n1 | cut -d'=' -f2 || true)"
    [[ -n "$preflight_ready" ]] || preflight_ready="0"
    echo "ORCHESTRATION_STEP preflight=$([[ "$preflight_rc" -eq 0 ]] && printf '%s' COMPLETED || printf '%s' FAILED)"
  fi

  completed_steps="audit"
  [[ "$install_rc" -eq 0 ]] && completed_steps="${completed_steps},install"
  [[ "${health_rc:-1}" -eq 0 ]] && completed_steps="${completed_steps},github_health_check"
  [[ "${snapshot_rc:-1}" -eq 0 ]] && completed_steps="${completed_steps},status_snapshot"
  [[ "${preflight_rc:-1}" -eq 0 ]] && completed_steps="${completed_steps},preflight"

  if [[ "$dry_run" == "1" ]]; then
    orchestrate_result="dry-run"
  elif [[ "$install_rc" -eq 0 && "$health_rc" -eq 0 && "$snapshot_rc" -eq 0 && "$preflight_ready" == "1" && "$daemon_status_head" == "RUNNING" && "$watchdog_status_head" == "RUNNING" ]]; then
    orchestrate_result="success"
  elif [[ "$daemon_status_head" == "RUNNING" || "$watchdog_status_head" == "RUNNING" || "$daemon_status_head" == "INSTALLED_NOT_LOADED" || "$watchdog_status_head" == "INSTALLED_NOT_LOADED" ]]; then
    orchestrate_result="partial"
  else
    orchestrate_result="failed"
  fi

  step_count="$(printf '%s' "$completed_steps" | awk -F',' '{print NF}')"
  manual_action_count="$(grep -c 'ACTION ' "$audit_output" || true)"

  echo "FINAL_SUMMARY result=${orchestrate_result}"
  echo "FINAL_SUMMARY completed_steps=${completed_steps}"
  echo "FINAL_SUMMARY completed_steps_count=${step_count}"
  echo "FINAL_SUMMARY daemon_status=${daemon_status}"
  echo "FINAL_SUMMARY watchdog_status=${watchdog_status}"
  echo "FINAL_SUMMARY github_health=${github_health}"
  echo "FINAL_SUMMARY snapshot_overall=${snapshot_overall}"
  [[ -n "$snapshot_headline" ]] && echo "FINAL_SUMMARY snapshot_headline=${snapshot_headline}"
  echo "FINAL_SUMMARY preflight_ready=${preflight_ready}"
  echo "FINAL_SUMMARY remaining_manual_actions=${manual_action_count}"
  emit_prefixed_entries "$preflight_output" "CHECKLIST" "SMOKE_CHECKLIST"
  emit_prefixed_entries "$preflight_output" "SMOKE_STEP" "SMOKE_STEP"
  echo "RECOVERY_RETRY ${retry_hint}"
  echo "RECOVERY_ROLLBACK ${rollback_hint}"

  if [[ "$dry_run" != "1" ]]; then
    mkdir -p "$tmp_root"
    {
      echo "PROFILE=${profile}"
      echo "RESULT=${orchestrate_result}"
      echo "AUDIT_OK=${audit_ok}"
      echo "AUDIT_WARN=${audit_warn}"
      echo "AUDIT_FAIL=${audit_fail}"
      echo "AUDIT_ACTION=${audit_action}"
      echo "INSTALL_RC=${install_rc}"
      echo "HEALTH_RC=${health_rc}"
      echo "SNAPSHOT_RC=${snapshot_rc}"
      echo "PREFLIGHT_RC=${preflight_rc}"
      echo "PREFLIGHT_READY=${preflight_ready}"
      echo "COMPLETED_STEPS=${completed_steps}"
      echo "DAEMON_STATUS=${daemon_status}"
      echo "WATCHDOG_STATUS=${watchdog_status}"
      echo "GITHUB_HEALTH=${github_health}"
      echo "SNAPSHOT_OVERALL=${snapshot_overall}"
      echo "SNAPSHOT_HEADLINE=${snapshot_headline}"
      echo "RETRY_HINT=${retry_hint}"
      echo "ROLLBACK_HINT=${rollback_hint}"
      emit_prefixed_entries "$audit_output" "ACTION" "MANUAL_ACTION"
      emit_prefixed_entries "$audit_output" "CHECK_FAIL" "BLOCKER"
      emit_prefixed_entries "$preflight_output" "CHECKLIST" "CHECKLIST"
    } >"$report_file"
    echo "ORCHESTRATION_REPORT=${report_file}"
  fi

  rm -f "$audit_output" "$install_output" "$health_output" "$snapshot_output" "$preflight_output"

  case "$orchestrate_result" in
    success|dry-run)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
  orchestrate)
    orchestrate_profile
    ;;
  *)
    echo "Unknown mode: ${mode}" >&2
    usage
    exit 1
    ;;
esac
