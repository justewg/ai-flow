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
  pr_list_open
  pr_view
  pr_create
  pr_edit
  commit_push
  project_set_status

Fixed input files in .tmp/codex:
  pr_number.txt
  pr_title.txt
  pr_body.txt
  commit_message.txt
  stage_paths.txt
  project_task_id.txt
  project_status.txt
  project_flow.txt (optional; defaults to project_status.txt)
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

cmd="${1:-help}"

case "$cmd" in
  help)
    usage
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

  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
