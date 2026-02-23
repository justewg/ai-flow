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
  project_new_status.txt (optional; defaults to Todo)
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
    new_status="Todo"
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

  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
