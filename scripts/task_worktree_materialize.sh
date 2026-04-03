#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> [title]"
  exit 1
fi

task_id="$1"
issue_number="$2"
task_title="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
CODEX_DIR="$(codex_export_state_dir)"
codex_resolve_flow_config
codex_resolve_project_profile_name >/dev/null 2>&1 || true

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name)"
task_key="$(task_worktree_key "$task_id" "$issue_number" "$profile_name")"
task_root="$(task_worktree_root_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_meta_dir="$(task_worktree_meta_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_logs_dir="$(task_worktree_logs_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_env_file="$(task_worktree_env_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_json_file="$(task_worktree_json_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
task_branch="$(task_worktree_resolve_branch "$task_id" "$issue_number" "$task_title" "$state_dir" "$profile_name")"
base_commit="$(git -C "${ROOT_DIR}" rev-parse "origin/${FLOW_HEAD_BRANCH}")"

mkdir -p "$task_meta_dir" "$task_logs_dir"

task_worktree_remove_existing() {
  if git -C "${ROOT_DIR}" worktree list --porcelain | grep -Fq "worktree ${task_repo}"; then
    git -C "${ROOT_DIR}" worktree remove --force "$task_repo" >/dev/null 2>&1 || true
  fi
  rm -rf "$task_root"
}

task_worktree_create_fresh() {
  task_worktree_remove_existing
  git -C "${ROOT_DIR}" worktree add -B "$task_branch" "$task_repo" "origin/${FLOW_HEAD_BRANCH}"
  mkdir -p "$task_meta_dir" "$task_logs_dir"
}

materialized_now="0"
recreated_reason=""
existing_base_commit=""

if task_worktree_repo_present "$task_repo"; then
  existing_base_commit="$(task_worktree_head_commit "$task_repo" || true)"
  if [[ -n "$existing_base_commit" && "$existing_base_commit" != "$base_commit" ]]; then
    task_worktree_remove_existing
    task_worktree_create_fresh
    materialized_now="1"
    recreated_reason="stale_base_commit"
  fi
else
  task_worktree_create_fresh
  materialized_now="1"
fi

toolkit_materialized="0"
if task_worktree_declares_toolkit_submodule "$task_repo"; then
  if ! task_worktree_ensure_toolkit_materialized "$task_repo"; then
    if [[ "$materialized_now" == "0" || "$TASK_WORKTREE_TOOLKIT_NEEDS_RECREATE" == "1" ]]; then
      task_worktree_remove_existing
      task_worktree_create_fresh
      materialized_now="1"
      if [[ "$TASK_WORKTREE_TOOLKIT_NEEDS_RECREATE" == "1" ]]; then
        recreated_reason="${recreated_reason:-toolkit_revision_missing}"
      else
        recreated_reason="${recreated_reason:-toolkit_init_retry}"
      fi
    fi
    if ! task_worktree_ensure_toolkit_materialized "$task_repo"; then
      echo "TASK_WORKTREE_TOOLKIT_INIT_FAILED=1"
      echo "TASK_WORKTREE_TOOLKIT_PATH=${task_repo}/.flow/shared"
      exit 1
    fi
  elif [[ "$materialized_now" == "0" && "$TASK_WORKTREE_TOOLKIT_NEEDS_RECREATE" == "1" ]]; then
    task_worktree_remove_existing
    task_worktree_create_fresh
    materialized_now="1"
    recreated_reason="${recreated_reason:-toolkit_revision_missing}"
    if ! task_worktree_ensure_toolkit_materialized "$task_repo"; then
      echo "TASK_WORKTREE_TOOLKIT_INIT_FAILED=1"
      echo "TASK_WORKTREE_TOOLKIT_PATH=${task_repo}/.flow/shared"
      exit 1
    fi
  fi
  toolkit_materialized="1"
fi

mkdir -p "$task_meta_dir" "$task_logs_dir"

claimed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$task_env_file" <<EOF
TASK_KEY=${task_key}
TASK_ID=${task_id}
ISSUE_NUMBER=${issue_number}
PROFILE=${profile_name}
BASE_BRANCH=${FLOW_BASE_BRANCH}
HEAD_BRANCH=${FLOW_HEAD_BRANCH}
TASK_BRANCH=${task_branch}
TASK_SLUG=$(task_worktree_slug_from_title "$task_title")
WORKTREE_PATH=${task_repo}
BASE_COMMIT=${base_commit}
CLAIMED_AT=${claimed_at}
CLAIMED_BY_RUNTIME_ID=${FLOW_AUTHORITATIVE_RUNTIME_ID:-}
EXECUTION_MODE=daemon
PR_NUMBER=
STATE=MATERIALIZED
EOF

jq -n \
  --arg task_key "$task_key" \
  --arg task_id "$task_id" \
  --arg issue_number "$issue_number" \
  --arg profile "$profile_name" \
  --arg base_branch "$FLOW_BASE_BRANCH" \
  --arg head_branch "$FLOW_HEAD_BRANCH" \
  --arg task_branch "$task_branch" \
  --arg task_slug "$(task_worktree_slug_from_title "$task_title")" \
  --arg worktree_path "$task_repo" \
  --arg base_commit "$base_commit" \
  --arg claimed_at "$claimed_at" \
  --arg claimed_by_runtime_id "${FLOW_AUTHORITATIVE_RUNTIME_ID:-}" \
  '{
    task_key: $task_key,
    task_id: $task_id,
    issue_number: $issue_number,
    profile: $profile,
    base_branch: $base_branch,
    head_branch: $head_branch,
    task_branch: $task_branch,
    task_slug: $task_slug,
    worktree_path: $worktree_path,
    base_commit: $base_commit,
    claimed_at: $claimed_at,
    claimed_by_runtime_id: $claimed_by_runtime_id,
    execution_mode: "daemon",
    pr_number: "",
    state: "MATERIALIZED",
    review_comment_id: "",
    blocker_comment_id: "",
    last_executor_exit_code: "",
    cleanup_started_at: "",
    cleanup_finished_at: "",
    terminal_reason: ""
  }' > "$task_json_file"

printf '%s\n' "$task_key" > "${CODEX_DIR}/daemon_active_task_key.txt"
printf '%s\n' "$task_repo" > "${CODEX_DIR}/daemon_active_worktree_path.txt"
printf '%s\n' "$task_branch" > "${CODEX_DIR}/daemon_active_task_branch.txt"

echo "TASK_WORKTREE_KEY=${task_key}"
echo "TASK_WORKTREE_PATH=${task_repo}"
echo "TASK_WORKTREE_BRANCH=${task_branch}"
echo "TASK_WORKTREE_BASE_COMMIT=${base_commit}"
echo "TASK_WORKTREE_MATERIALIZED=${materialized_now}"
echo "TASK_WORKTREE_TOOLKIT_MATERIALIZED=${toolkit_materialized}"
if [[ -n "$recreated_reason" ]]; then
  echo "TASK_WORKTREE_RECREATED=1"
  echo "TASK_WORKTREE_RECREATE_REASON=${recreated_reason}"
fi
