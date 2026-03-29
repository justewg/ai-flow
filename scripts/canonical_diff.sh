#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <task-id> <issue-number>"
  exit 1
fi

task_id="$1"
issue_number="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
execution_dir="$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
diff_file="$(task_worktree_canonical_diff_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
changed_files_file="$(task_worktree_changed_files_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
summary_file="$(task_worktree_diff_summary_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$execution_dir"

git -C "$task_repo" diff --no-ext-diff --unified=3 -- . > "$diff_file"

changed_files_json="$(
  git -C "$task_repo" diff --name-only -- . \
    | awk 'NF > 0' \
    | jq -R . \
    | jq -s '.'
)"

printf '%s\n' "$changed_files_json" > "$changed_files_file"

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg diffFile "$diff_file" \
  --argjson changedFiles "$changed_files_json" \
  --arg diffStat "$(git -C "$task_repo" diff --stat -- . || true)" \
  '{
    taskId:$taskId,
    issueNumber:$issueNumber,
    diffFile:$diffFile,
    changedFiles:$changedFiles,
    diffStat:$diffStat
  }' > "$summary_file"

echo "CANONICAL_DIFF_READY=1"
echo "CANONICAL_DIFF_FILE=${diff_file}"
echo "CHANGED_FILES_FILE=${changed_files_file}"
echo "DIFF_SUMMARY_FILE=${summary_file}"
