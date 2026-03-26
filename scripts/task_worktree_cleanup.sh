#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> [reason]"
  exit 1
fi

task_id="$1"
issue_number="$2"
cleanup_reason="${3:-terminal}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
CODEX_DIR="$(codex_export_state_dir)"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name)"

task_root="$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_meta_dir="$(task_worktree_meta_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_env_file="$(task_worktree_env_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_branch="$(task_worktree_read_env_value "$task_env_file" "TASK_BRANCH" || true)"
executor_pid="$(cat "${CODEX_DIR}/executor_pid.txt" 2>/dev/null || true)"
executor_task_id="$(cat "${CODEX_DIR}/executor_task_id.txt" 2>/dev/null || true)"
active_task_id="$(cat "${CODEX_DIR}/daemon_active_task.txt" 2>/dev/null || true)"

if [[ "$executor_task_id" == "$task_id" && "$executor_pid" =~ ^[0-9]+$ ]] && kill -0 "$executor_pid" 2>/dev/null; then
  echo "TASK_WORKTREE_CLEANUP_SKIPPED=EXECUTOR_RUNNING"
  echo "TASK_WORKTREE_CLEANUP_TASK_ID=${task_id}"
  echo "TASK_WORKTREE_CLEANUP_ISSUE_NUMBER=${issue_number}"
  exit 0
fi

if [[ ! -d "$task_root" ]]; then
  echo "TASK_WORKTREE_CLEANUP_NOOP=ABSENT"
  echo "TASK_WORKTREE_CLEANUP_TASK_ID=${task_id}"
  echo "TASK_WORKTREE_CLEANUP_ISSUE_NUMBER=${issue_number}"
  exit 0
fi

if [[ -n "$task_branch" && "$task_branch" != "$FLOW_HEAD_BRANCH" && "$task_branch" != "$FLOW_BASE_BRANCH" ]]; then
  if git -C "${ROOT_DIR}" ls-remote --exit-code --heads origin "$task_branch" >/dev/null 2>&1; then
    if git -C "${ROOT_DIR}" push origin --delete "$task_branch" >/dev/null 2>&1; then
      echo "TASK_WORKTREE_REMOTE_BRANCH_DELETED=1"
      echo "TASK_WORKTREE_BRANCH=${task_branch}"
    else
      echo "TASK_WORKTREE_REMOTE_BRANCH_DELETE_SKIPPED=1"
      echo "TASK_WORKTREE_BRANCH=${task_branch}"
    fi
  fi
fi

if git -C "${ROOT_DIR}" worktree list --porcelain | grep -Fq "worktree ${task_repo}"; then
  git -C "${ROOT_DIR}" worktree remove --force "$task_repo"
  echo "TASK_WORKTREE_REMOVED=1"
else
  rm -rf "$task_root"
  echo "TASK_WORKTREE_REMOVED=1"
fi

rm -rf "$task_root"

if [[ "$active_task_id" == "$task_id" ]]; then
  : > "${CODEX_DIR}/daemon_active_task.txt"
  : > "${CODEX_DIR}/daemon_active_item_id.txt"
  : > "${CODEX_DIR}/daemon_active_issue_number.txt"
  : > "${CODEX_DIR}/daemon_active_task_key.txt"
  : > "${CODEX_DIR}/daemon_active_worktree_path.txt"
  : > "${CODEX_DIR}/daemon_active_task_branch.txt"
  : > "${CODEX_DIR}/project_task_id.txt"
  echo "TASK_WORKTREE_ACTIVE_CONTEXT_CLEARED=1"
fi

echo "TASK_WORKTREE_CLEANUP_DONE=1"
echo "TASK_WORKTREE_CLEANUP_REASON=${cleanup_reason}"
echo "TASK_WORKTREE_CLEANUP_TASK_ID=${task_id}"
echo "TASK_WORKTREE_CLEANUP_ISSUE_NUMBER=${issue_number}"
