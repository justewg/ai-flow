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

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
execution_profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
intake_profile_file="$(task_worktree_intake_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_interpret.sh" "$task_id" "$issue_number" >/dev/null

intake_json="$(cat "$intake_profile_file")"
spec_json="$(cat "$spec_file")"
decision="$(printf '%s' "$intake_json" | jq -r '.profileDecision // "standard"')"
decision_reason="$(printf '%s' "$intake_json" | jq -r '.decisionReason // ""')"
target_count="$(printf '%s' "$intake_json" | jq -r '(.candidateTargetFiles // []) | length')"

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg profile "$decision" \
  --arg decision "$decision" \
  --arg reason "$decision_reason" \
  --arg sourceDefinitionFile "$source_file" \
  --arg standardizedTaskSpecFile "$spec_file" \
  --arg intakeProfileFile "$intake_profile_file" \
  --arg interpretedIntent "$(printf '%s' "$spec_json" | jq -r '.interpretedIntent // ""')" \
  --argjson candidateTargetFiles "$(printf '%s' "$spec_json" | jq -c '.candidateTargetFiles // []')" \
  --argjson confidence "$(printf '%s' "$spec_json" | jq -c '.confidence // {}')" \
  --argjson rationale "$(printf '%s' "$spec_json" | jq -c '.rationale // []')" \
  '{
    taskId:$taskId,
    issueNumber:$issueNumber,
    profile:$profile,
    decision:$decision,
    reason:$reason,
    sourceDefinitionFile:$sourceDefinitionFile,
    standardizedTaskSpecFile:$standardizedTaskSpecFile,
    intakeProfileFile:$intakeProfileFile,
    interpretedIntent:$interpretedIntent,
    candidateTargetFiles:$candidateTargetFiles,
    confidence:$confidence,
    rationale:$rationale
  }' > "$execution_profile_file"

if [[ -n "$output_file" ]]; then
  if [[ "$output_file" != "$execution_profile_file" ]]; then
    cp "$execution_profile_file" "$output_file"
  fi
fi

echo "EXECUTION_PROFILE=${decision}"
[[ -n "$decision_reason" ]] && echo "EXECUTION_PROFILE_REASON=${decision_reason}"
echo "EXECUTION_PROFILE_TARGET_COUNT=${target_count}"
cat "$execution_profile_file"
