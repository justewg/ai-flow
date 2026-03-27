#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

ROOT_DIR="$(codex_resolve_root_dir)"
AI_FLOW_ROOT_DIR="$(codex_resolve_ai_flow_root_dir)"
PROJECT_PROFILE="$(codex_resolve_project_profile_name)"
STATE_DIR="$(codex_export_state_dir)"
COMPOSE_ROOT="${AI_FLOW_ROOT_DIR}/docker/${PROJECT_PROFILE}"

clear_state_file() {
  local name="$1"
  : > "${STATE_DIR}/${name}"
}

refresh_branch() {
  local branch="$1"
  git -C "$ROOT_DIR" checkout "$branch"
  git -C "$ROOT_DIR" reset --hard "origin/${branch}"
}

if [[ -e "${ROOT_DIR}/.flow/shared/.git" ]]; then
  git -C "${ROOT_DIR}/.flow/shared" reset --hard
  git -C "${ROOT_DIR}/.flow/shared" clean -fd
fi

git -C "$ROOT_DIR" fetch origin
refresh_branch "development"
refresh_branch "main"
git -C "$ROOT_DIR" checkout development
git -C "$ROOT_DIR" submodule sync --recursive
git -C "$ROOT_DIR" submodule update --init --recursive --force --checkout .flow/shared
git -C "$ROOT_DIR" clean -fd

clear_state_file "daemon_active_task.txt"
clear_state_file "daemon_active_item_id.txt"
clear_state_file "daemon_active_issue_number.txt"
clear_state_file "daemon_waiting_task_id.txt"
clear_state_file "daemon_waiting_issue_number.txt"
clear_state_file "daemon_waiting_kind.txt"
clear_state_file "daemon_waiting_since_utc.txt"
clear_state_file "daemon_waiting_comment_url.txt"
clear_state_file "daemon_waiting_pending_post.txt"
clear_state_file "daemon_waiting_question_comment_id.txt"
clear_state_file "daemon_review_task_id.txt"
clear_state_file "daemon_review_item_id.txt"
clear_state_file "daemon_review_issue_number.txt"
clear_state_file "daemon_review_pr_number.txt"
clear_state_file "daemon_review_branch_name.txt"

if [[ -f "${COMPOSE_ROOT}/docker-compose.yml" && -f "${COMPOSE_ROOT}/.env" ]]; then
  docker compose --env-file "${COMPOSE_ROOT}/.env" -f "${COMPOSE_ROOT}/docker-compose.yml" restart daemon
fi

git -C "$ROOT_DIR" status --short
git -C "$ROOT_DIR" submodule status
git -C "${ROOT_DIR}/.flow/shared" rev-parse --short HEAD
if [[ -f "${SCRIPT_DIR}/status_snapshot.sh" ]]; then
  "${SCRIPT_DIR}/status_snapshot.sh"
fi
