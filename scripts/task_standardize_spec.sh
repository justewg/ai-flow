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
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
if [[ ! -d "$task_repo/.git" && ! -f "$task_repo/.git" ]]; then
  task_repo="${ROOT_DIR}"
fi
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$(dirname "$spec_file")"

if [[ ! -f "$source_file" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_capture_source_definition.sh" "$task_id" "$issue_number" >/dev/null
fi

source_json="$(cat "$source_file")"
issue_title="$(printf '%s' "$source_json" | jq -r '.title // ""')"
issue_body="$(printf '%s' "$source_json" | jq -r '.body // ""')"
reply_text="$(printf '%s' "$source_json" | jq -r '.replyText // ""')"
source_hash="$(printf '%s' "$source_json" | jq -r '.sourceHash // ""')"
combined_text="$(printf '%s\n%s\n%s' "$issue_title" "$issue_body" "$reply_text")"
interpreted_intent="$(task_intake_interpreted_intent "$issue_title" "$issue_body" "$reply_text")"

target_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  target_files+=("$line")
done < <(micro_profile_extract_target_files "$combined_text" "$task_repo" || true)

expected_change_json='[]'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done < <(task_intake_extract_expected_change_lines "$issue_body" || true) \
  | jq -R . | jq -s '.' > /tmp/task_standardize_expected_change.json
expected_change_json="$(cat /tmp/task_standardize_expected_change.json)"
rm -f /tmp/task_standardize_expected_change.json

notes_json='[]'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done < <(task_intake_extract_notes_lines "$issue_body" || true) \
  | jq -R . | jq -s '.' > /tmp/task_standardize_notes.json
notes_json="$(cat /tmp/task_standardize_notes.json)"
rm -f /tmp/task_standardize_notes.json

check_commands_json='[]'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done < <(micro_profile_extract_check_commands "$issue_body" || true) \
  | jq -R . | jq -s '.' > /tmp/task_standardize_checks.json
check_commands_json="$(cat /tmp/task_standardize_checks.json)"
rm -f /tmp/task_standardize_checks.json

target_files_json='[]'
if (( ${#target_files[@]} > 0 )); then
  target_files_json="$(
    for path in "${target_files[@]}"; do
      printf '%s\n' "$path"
    done | jq -R . | jq -s '.'
  )"
fi

decision_json="$(task_intake_profile_decision_json "$combined_text" "${#target_files[@]}" "$target_files_json" "$interpreted_intent")"

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg sourceHash "$source_hash" \
  --arg interpretedIntent "$interpreted_intent" \
  --arg repo "$REPO" \
  --arg repoRoot "$task_repo" \
  --arg profileName "$profile_name" \
  --argjson decision "$decision_json" \
  --argjson candidateTargetFiles "$target_files_json" \
  --argjson expectedChange "$expected_change_json" \
  --argjson checks "$check_commands_json" \
  --argjson notes "$notes_json" \
  '{
    kind:"standardized_task_spec",
    taskId:$taskId,
    issueNumber:$issueNumber,
    sourceHash:$sourceHash,
    profileDecision:$decision.profileDecision,
    decisionReason:$decision.reason,
    interpretedIntent:$interpretedIntent,
    candidateTargetFiles:$candidateTargetFiles,
    expectedChange:$expectedChange,
    checks:$checks,
    confidence:$decision.confidence,
    notes:$notes,
    rationale:$decision.rationale,
    repositoryContext:{
      repo:$repo,
      repoRoot:$repoRoot,
      profileName:$profileName
    }
  }' > "$spec_file"

if [[ -n "$output_file" ]]; then
  cp "$spec_file" "$output_file"
fi

echo "STANDARDIZED_TASK_SPEC_READY=1"
echo "STANDARDIZED_TASK_SPEC_FILE=${spec_file}"
cat "$spec_file"
