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
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
intake_profile_file="$(task_worktree_intake_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$(dirname "$intake_profile_file")"

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_capture_source_definition.sh" "$task_id" "$issue_number" >/dev/null
/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_standardize_spec.sh" "$task_id" "$issue_number" >/dev/null

source_json="$(cat "$source_file")"
spec_json="$(cat "$spec_file")"

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg sourceDefinitionFile "$source_file" \
  --arg standardizedTaskSpecFile "$spec_file" \
  --arg sourceHash "$(printf '%s' "$source_json" | jq -r '.sourceHash // ""')" \
  --arg profileDecision "$(printf '%s' "$spec_json" | jq -r '.profileDecision // "standard"')" \
  --arg decisionReason "$(printf '%s' "$spec_json" | jq -r '.decisionReason // ""')" \
  --arg interpretedIntent "$(printf '%s' "$spec_json" | jq -r '.interpretedIntent // ""')" \
  --argjson candidateTargetFiles "$(printf '%s' "$spec_json" | jq -c '.candidateTargetFiles // []')" \
  --argjson confidence "$(printf '%s' "$spec_json" | jq -c '.confidence // {}')" \
  --argjson rationale "$(printf '%s' "$spec_json" | jq -c '.rationale // []')" \
  '{
    kind:"intake_profile",
    taskId:$taskId,
    issueNumber:$issueNumber,
    sourceDefinitionFile:$sourceDefinitionFile,
    standardizedTaskSpecFile:$standardizedTaskSpecFile,
    sourceHash:$sourceHash,
    profileDecision:$profileDecision,
    decisionReason:$decisionReason,
    interpretedIntent:$interpretedIntent,
    candidateTargetFiles:$candidateTargetFiles,
    confidence:$confidence,
    rationale:$rationale
  }' > "$intake_profile_file"

if [[ -n "$output_file" ]]; then
  cp "$intake_profile_file" "$output_file"
fi

echo "TASK_INTERPRETATION_READY=1"
echo "SOURCE_DEFINITION_FILE=${source_file}"
echo "STANDARDIZED_TASK_SPEC_FILE=${spec_file}"
echo "INTAKE_PROFILE_FILE=${intake_profile_file}"
cat "$intake_profile_file"
