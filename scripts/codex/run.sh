#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

mkdir -p "${CODEX_DIR}"

usage() {
  cat <<'EOF'
Usage: scripts/codex/run.sh <command>

Commands:
  help
  clear
  write
  append
  copy
  sync_branches
  pr_list_open
  pr_view
  pr_create
  pr_edit
  commit_push
  project_add_task
  project_set_status
  next_task
  daemon_tick
  daemon_loop
  daemon_install
  daemon_uninstall
  daemon_status
  watchdog_tick
  watchdog_loop
  watchdog_install
  watchdog_uninstall
  watchdog_status
  executor_reset
  executor_start
  executor_tick
  executor_build_prompt
  task_ask
  daemon_check_replies
  task_finalize
  gh_retry
  github_health_check
  github_outbox

Fixed input files in .tmp/codex:
  pr_number.txt
  pr_title.txt
  pr_body.txt
  commit_message.txt
  stage_paths.txt
  project_task_id.txt
  project_status.txt
  project_flow.txt (optional; defaults to project_status.txt)
  project_new_task_id.txt
  project_new_title.txt
  project_new_scope.txt
  project_new_priority.txt
  project_new_status.txt (optional; defaults to Backlog)
  project_new_flow.txt (optional; defaults to Backlog)
EOF
}

read_required_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing file: $file_path"
    exit 1
  fi
  local content
  content="$(<"$file_path")"
  if [[ -z "$content" ]]; then
    echo "Empty file: $file_path"
    exit 1
  fi
  printf '%s' "$content"
}

key_to_file() {
  local key="$1"
  case "$key" in
    pr_number) echo "${CODEX_DIR}/pr_number.txt" ;;
    pr_title) echo "${CODEX_DIR}/pr_title.txt" ;;
    pr_body) echo "${CODEX_DIR}/pr_body.txt" ;;
    commit_message) echo "${CODEX_DIR}/commit_message.txt" ;;
    stage_paths) echo "${CODEX_DIR}/stage_paths.txt" ;;
    project_task_id) echo "${CODEX_DIR}/project_task_id.txt" ;;
    project_status) echo "${CODEX_DIR}/project_status.txt" ;;
    project_flow) echo "${CODEX_DIR}/project_flow.txt" ;;
    project_new_task_id) echo "${CODEX_DIR}/project_new_task_id.txt" ;;
    project_new_title) echo "${CODEX_DIR}/project_new_title.txt" ;;
    project_new_scope) echo "${CODEX_DIR}/project_new_scope.txt" ;;
    project_new_priority) echo "${CODEX_DIR}/project_new_priority.txt" ;;
    project_new_status) echo "${CODEX_DIR}/project_new_status.txt" ;;
    project_new_flow) echo "${CODEX_DIR}/project_new_flow.txt" ;;
    *)
      echo "Unknown key: $key"
      exit 1
      ;;
  esac
}

cmd="${1:-help}"

case "$cmd" in
  help)
    usage
    ;;

  clear)
    if [[ $# -ne 2 ]]; then
      echo "Usage: scripts/codex/run.sh clear <key>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    : > "$file_path"
    ;;

  write)
    if [[ $# -lt 3 ]]; then
      echo "Usage: scripts/codex/run.sh write <key> <value...>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    shift 2
    # Interpret escaped sequences (for example: \n -> newline) for PR bodies.
    printf '%b\n' "$*" > "$file_path"
    ;;

  append)
    if [[ $# -lt 3 ]]; then
      echo "Usage: scripts/codex/run.sh append <key> <value...>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    shift 2
    # Interpret escaped sequences (for example: \n -> newline) for multiline payloads.
    printf '%b\n' "$*" >> "$file_path"
    ;;

  copy)
    if [[ $# -ne 3 ]]; then
      echo "Usage: scripts/codex/run.sh copy <key> <source-file>"
      exit 1
    fi
    file_path="$(key_to_file "$2")"
    source_file="$3"
    if [[ ! -f "$source_file" ]]; then
      echo "Source file not found: $source_file"
      exit 1
    fi
    cp "$source_file" "$file_path"
    ;;

  sync_branches)
    "${ROOT_DIR}/scripts/codex/sync_branches.sh"
    ;;

  pr_list_open)
    "${ROOT_DIR}/scripts/codex/pr_list_open.sh"
    ;;

  pr_view)
    pr_number="$(read_required_file "${CODEX_DIR}/pr_number.txt")"
    "${ROOT_DIR}/scripts/codex/pr_view.sh" "$pr_number"
    ;;

  pr_create)
    "${ROOT_DIR}/scripts/codex/pr_create.sh" \
      "${CODEX_DIR}/pr_title.txt" \
      "${CODEX_DIR}/pr_body.txt"
    ;;

  pr_edit)
    pr_number="$(read_required_file "${CODEX_DIR}/pr_number.txt")"
    "${ROOT_DIR}/scripts/codex/pr_edit.sh" \
      "$pr_number" \
      "${CODEX_DIR}/pr_title.txt" \
      "${CODEX_DIR}/pr_body.txt"
    ;;

  commit_push)
    commit_message="$(read_required_file "${CODEX_DIR}/commit_message.txt")"
    stage_paths=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      stage_paths+=("$line")
    done < "${CODEX_DIR}/stage_paths.txt"
    if [[ ${#stage_paths[@]} -eq 0 ]]; then
      echo "Missing or empty file: ${CODEX_DIR}/stage_paths.txt"
      exit 1
    fi
    "${ROOT_DIR}/scripts/codex/dev_commit_push.sh" "$commit_message" "${stage_paths[@]}"
    ;;

  project_add_task)
    new_task_id="$(read_required_file "${CODEX_DIR}/project_new_task_id.txt")"
    new_scope="$(read_required_file "${CODEX_DIR}/project_new_scope.txt")"
    new_priority="$(read_required_file "${CODEX_DIR}/project_new_priority.txt")"
    new_status="Backlog"
    new_flow="Backlog"
    [[ -f "${CODEX_DIR}/project_new_status.txt" ]] && new_status="$(read_required_file "${CODEX_DIR}/project_new_status.txt")"
    [[ -f "${CODEX_DIR}/project_new_flow.txt" ]] && new_flow="$(read_required_file "${CODEX_DIR}/project_new_flow.txt")"
    "${ROOT_DIR}/scripts/codex/project_add_task.sh" \
      "$new_task_id" \
      "${CODEX_DIR}/project_new_title.txt" \
      "$new_scope" \
      "$new_priority" \
      "$new_status" \
      "$new_flow"
    ;;

  project_set_status)
    task_id="$(read_required_file "${CODEX_DIR}/project_task_id.txt")"
    status_name="$(read_required_file "${CODEX_DIR}/project_status.txt")"
    flow_file="${CODEX_DIR}/project_flow.txt"
    if [[ -f "$flow_file" ]]; then
      flow_name="$(read_required_file "$flow_file")"
      "${ROOT_DIR}/scripts/codex/project_set_status.sh" "$task_id" "$status_name" "$flow_name"
    else
      "${ROOT_DIR}/scripts/codex/project_set_status.sh" "$task_id" "$status_name"
    fi
    ;;

  next_task)
    "${ROOT_DIR}/scripts/codex/next_task.sh"
    ;;

  daemon_tick)
    "${ROOT_DIR}/scripts/codex/daemon_tick.sh"
    ;;

  daemon_loop)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/daemon_loop.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/daemon_loop.sh"
    fi
    ;;

  daemon_install)
    if [[ $# -ge 3 ]]; then
      "${ROOT_DIR}/scripts/codex/daemon_install.sh" "$2" "$3"
    elif [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/daemon_install.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/daemon_install.sh"
    fi
    ;;

  daemon_uninstall)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/daemon_uninstall.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/daemon_uninstall.sh"
    fi
    ;;

  daemon_status)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/daemon_status.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/daemon_status.sh"
    fi
    ;;

  watchdog_tick)
    "${ROOT_DIR}/scripts/codex/watchdog_tick.sh"
    ;;

  watchdog_loop)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/watchdog_loop.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/watchdog_loop.sh"
    fi
    ;;

  watchdog_install)
    if [[ $# -ge 3 ]]; then
      "${ROOT_DIR}/scripts/codex/watchdog_install.sh" "$2" "$3"
    elif [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/watchdog_install.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/watchdog_install.sh"
    fi
    ;;

  watchdog_uninstall)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/watchdog_uninstall.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/watchdog_uninstall.sh"
    fi
    ;;

  watchdog_status)
    if [[ $# -ge 2 ]]; then
      "${ROOT_DIR}/scripts/codex/watchdog_status.sh" "$2"
    else
      "${ROOT_DIR}/scripts/codex/watchdog_status.sh"
    fi
    ;;

  executor_reset)
    "${ROOT_DIR}/scripts/codex/executor_reset.sh"
    ;;

  executor_start)
    if [[ $# -ne 3 ]]; then
      echo "Usage: scripts/codex/run.sh executor_start <task-id> <issue-number>"
      exit 1
    fi
    "${ROOT_DIR}/scripts/codex/executor_start.sh" "$2" "$3"
    ;;

  executor_tick)
    if [[ $# -ne 3 ]]; then
      echo "Usage: scripts/codex/run.sh executor_tick <task-id> <issue-number>"
      exit 1
    fi
    "${ROOT_DIR}/scripts/codex/executor_tick.sh" "$2" "$3"
    ;;

  executor_build_prompt)
    if [[ $# -ne 4 ]]; then
      echo "Usage: scripts/codex/run.sh executor_build_prompt <task-id> <issue-number> <output-file>"
      exit 1
    fi
    "${ROOT_DIR}/scripts/codex/executor_build_prompt.sh" "$2" "$3" "$4"
    ;;

  task_ask)
    if [[ $# -ne 3 ]]; then
      echo "Usage: scripts/codex/run.sh task_ask <question|blocker> <message-file>"
      exit 1
    fi
    "${ROOT_DIR}/scripts/codex/task_ask.sh" "$2" "$3"
    ;;

  daemon_check_replies)
    "${ROOT_DIR}/scripts/codex/daemon_check_replies.sh"
    ;;

  task_finalize)
    "${ROOT_DIR}/scripts/codex/task_finalize.sh"
    ;;

  gh_retry)
    if [[ $# -lt 2 ]]; then
      echo "Usage: scripts/codex/run.sh gh_retry <command> [args...]"
      exit 1
    fi
    shift 1
    "${ROOT_DIR}/scripts/codex/gh_retry.sh" "$@"
    ;;

  github_health_check)
    "${ROOT_DIR}/scripts/codex/github_health_check.sh"
    ;;

  github_outbox)
    if [[ $# -lt 2 ]]; then
      echo "Usage: scripts/codex/run.sh github_outbox <enqueue_issue_comment|flush|count|list> [args...]"
      exit 1
    fi
    shift 1
    "${ROOT_DIR}/scripts/codex/github_outbox.sh" "$@"
    ;;

  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
