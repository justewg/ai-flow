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
budget_file="$(task_worktree_execution_budget_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

if [[ ! -f "$budget_file" ]]; then
  echo "MICRO_PROFILE_GUARD_READY=0"
  echo "MICRO_PROFILE_GUARD_REASON=missing_budget_file"
  exit 0
fi

profile_breach="$(jq -r '.profileBreach // false' "$budget_file")"
enforce_breach="$(jq -r '.enforceProfileBreach // false' "$budget_file")"

echo "MICRO_PROFILE_GUARD_READY=1"
echo "MICRO_PROFILE_BREACH=${profile_breach}"
echo "MICRO_PROFILE_ENFORCE=${enforce_breach}"

if [[ "$profile_breach" == "true" && "$enforce_breach" == "true" ]]; then
  echo "FAILED_PROFILE_BREACH=1"
  exit 42
fi

exit 0
