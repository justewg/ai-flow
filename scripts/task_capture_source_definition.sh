#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <issue-number> [output-file]"
  exit 1
fi

task_id="$1"
issue_number="$2"
output_file="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env/bootstrap.sh"
source "${SCRIPT_DIR}/task_worktree_lib.sh"
source "${SCRIPT_DIR}/micro_profile_lib.sh"
source "${SCRIPT_DIR}/task_intake_lib.sh"

REPO="${GITHUB_REPO:-justewg/planka}"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$(dirname "$source_file")"

issue_json="$(task_intake_issue_json "$issue_number" "$REPO" 2>/dev/null || jq -nc --arg n "$issue_number" '{title:"", body:"", number:$n}')"
issue_title="$(task_intake_issue_title "$issue_json")"
issue_body="$(task_intake_issue_body "$issue_json")"
reply_text="$(task_intake_reply_text "$task_id")"

if [[ -n "${TASK_INTAKE_SOURCE_TITLE:-}" ]]; then
  issue_title="${TASK_INTAKE_SOURCE_TITLE}"
fi
if [[ -n "${TASK_INTAKE_SOURCE_BODY:-}" ]]; then
  issue_body="${TASK_INTAKE_SOURCE_BODY}"
fi
if [[ -n "${TASK_INTAKE_SOURCE_REPLY:-}" ]]; then
  reply_text="${TASK_INTAKE_SOURCE_REPLY}"
fi

task_intake_compose_source_json \
  "$task_id" \
  "$issue_number" \
  "$REPO" \
  "$profile_name" \
  "$issue_json" \
  "$issue_title" \
  "$issue_body" \
  "$reply_text" > "$source_file"

if [[ -n "$output_file" ]]; then
  cp "$source_file" "$output_file"
fi

echo "SOURCE_DEFINITION_READY=1"
echo "SOURCE_DEFINITION_FILE=${source_file}"
cat "$source_file"
