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
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
# shellcheck source=./micro_profile_lib.sh
source "${SCRIPT_DIR}/micro_profile_lib.sh"

CODEX_DIR="$(codex_export_state_dir)"
REPO="${GITHUB_REPO:-justewg/planka}"
state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
mkdir -p "$CODEX_DIR"

issue_json="$(micro_profile_issue_json "$issue_number" "$REPO" 2>/dev/null || jq -nc --arg n "$issue_number" '{title:"", body:"", number:$n}')"
issue_title="$(micro_profile_issue_title "$issue_json")"
issue_body="$(micro_profile_issue_body "$issue_json")"
combined_text="$(printf '%s\n%s' "$issue_title" "$issue_body")"
combined_downcased="$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')"

target_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  target_files+=("$line")
done < <(micro_profile_extract_target_files "$combined_text" "$ROOT_DIR" || true)
target_count="${#target_files[@]}"
profile_kind="standard"
profile_reason="micro_classifier_default_standard"

denied_terms=(
  ".flow/shared"
  ".github/"
  "docker"
  "workflow"
  "ci"
  "auth"
  "finalize"
  "watchdog"
  "daemon"
  "executor"
  "submodule"
  "runtime-v2"
  "runtime_v2"
  "infra"
  "toolkit"
)

for denied in "${denied_terms[@]}"; do
  if [[ "$combined_downcased" == *"$denied"* ]]; then
    profile_reason="micro_classifier_denied_${denied//[^a-z0-9]/_}"
    break
  fi
done

if [[ "$profile_reason" == "micro_classifier_default_standard" ]]; then
  if (( target_count == 0 || target_count > 2 )); then
    profile_reason="micro_classifier_target_count_${target_count}"
  elif ! printf '%s' "$combined_downcased" | rg -q '\b(alias|readme|docs|documentation|help|label|usage|copy|rename|dispatch)\b'; then
    profile_reason="micro_classifier_not_small_text_or_alias_change"
  else
    profile_kind="micro"
    profile_reason="micro_classifier_small_textual_change"
  fi
fi

target_files_json='[]'
if (( target_count > 0 )); then
  target_files_json="$(
    for path in "${target_files[@]}"; do
      printf '%s\n' "$path"
    done | jq -R . | jq -s '.'
  )"
fi

json_payload="$(
  jq -nc \
    --arg taskId "$task_id" \
    --arg issueNumber "$issue_number" \
    --arg profile "$profile_kind" \
    --arg reason "$profile_reason" \
    --arg issueTitle "$issue_title" \
    --arg issueBody "$issue_body" \
    --argjson targetFiles "$target_files_json" \
    '{
      taskId:$taskId,
      issueNumber:$issueNumber,
      profile:$profile,
      reason:$reason,
      issueTitle:$issueTitle,
      issueBody:$issueBody,
      targetFiles:$targetFiles
    }'
)"

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname "$output_file")"
  printf '%s\n' "$json_payload" > "$output_file"
fi

echo "EXECUTION_PROFILE=${profile_kind}"
echo "EXECUTION_PROFILE_REASON=${profile_reason}"
echo "EXECUTION_PROFILE_TARGET_COUNT=${target_count}"
printf '%s\n' "$json_payload"
