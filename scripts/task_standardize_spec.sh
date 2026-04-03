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
interpretation_request_file="$(task_worktree_intake_interpretation_request_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
interpretation_response_file="$(task_worktree_intake_interpretation_response_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
interpretation_local_response_file="$(task_worktree_intake_interpretation_local_response_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
interpretation_claude_response_file="$(task_worktree_intake_interpretation_claude_response_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
interpretation_compare_file="$(task_worktree_intake_interpretation_compare_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

resolve_provider_compare_json() {
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/provider_compare_resolve.sh" --module "intake.interpretation"
}

write_shadow_error_artifact() {
  local output_file="$1"
  local provider_result_json="$2"
  jq -nc \
    --argjson providerResult "$provider_result_json" \
    '{
      _shadowProviderError: {
        requestId: ($providerResult.requestId // null),
        provider: ($providerResult.provider // "claude"),
        outcome: ($providerResult.outcome // "error"),
        errorClass: ($providerResult.errorClass // "shadow_provider_error"),
        errorMessage: ($providerResult.errorMessage // null),
        latencyMs: ($providerResult.latencyMs // null),
        tokenUsage: ($providerResult.tokenUsage // null),
        estimatedCost: ($providerResult.estimatedCost // null)
      }
    }' > "$output_file"
}

append_shadow_compare_telemetry() {
  local compare_json="$1"
  local provider_result_json="$2"
  local compare_artifact_json="$3"
  local schema_valid_primary
  local schema_valid_shadow
  local profile_match
  local target_files_match
  local human_needed_match

  schema_valid_primary="$(printf '%s' "$compare_artifact_json" | jq -r 'if .schemaValidPrimary == null then empty else .schemaValidPrimary end')"
  schema_valid_shadow="$(printf '%s' "$compare_artifact_json" | jq -r 'if .schemaValidShadow == null then empty else .schemaValidShadow end')"
  profile_match="$(printf '%s' "$compare_artifact_json" | jq -r 'if .profileMatch == null then empty else .profileMatch end')"
  target_files_match="$(printf '%s' "$compare_artifact_json" | jq -r 'if .targetFilesMatch == null then empty else .targetFilesMatch end')"
  human_needed_match="$(printf '%s' "$compare_artifact_json" | jq -r 'if .humanNeededMatch == null then empty else .humanNeededMatch end')"

  PROVIDER_TELEMETRY_LATENCY_MS="$(printf '%s' "$provider_result_json" | jq -r '.latencyMs // empty')" \
  PROVIDER_TELEMETRY_TOKEN_USAGE="$(printf '%s' "$provider_result_json" | jq -r '.tokenUsage // empty')" \
  PROVIDER_TELEMETRY_ESTIMATED_COST="$(printf '%s' "$provider_result_json" | jq -r '.estimatedCost // empty')" \
  PROVIDER_TELEMETRY_COMPARE_MODE="$(printf '%s' "$compare_json" | jq -r '.mode // ""')" \
  PROVIDER_TELEMETRY_PRIMARY_PROVIDER="local" \
  PROVIDER_TELEMETRY_SHADOW_PROVIDER="$(printf '%s' "$compare_json" | jq -r '.shadowProvider // "claude"')" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_PRIMARY="$schema_valid_primary" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_SHADOW="$schema_valid_shadow" \
  PROVIDER_TELEMETRY_PROFILE_MATCH="$profile_match" \
  PROVIDER_TELEMETRY_TARGET_FILES_MATCH="$target_files_match" \
  PROVIDER_TELEMETRY_HUMAN_NEEDED_MATCH="$human_needed_match" \
  PROVIDER_TELEMETRY_CONFIDENCE_DELTA="$(printf '%s' "$compare_artifact_json" | jq -r '.confidenceDelta // empty')" \
  PROVIDER_TELEMETRY_COMPARE_SUMMARY="$(printf '%s' "$compare_artifact_json" | jq -r '.compareSummary // ""')" \
  PROVIDER_TELEMETRY_PUBLISH_DECISION=0 \
  PROVIDER_TELEMETRY_DECISION_REASON="claude_shadow_compare" \
  PROVIDER_TELEMETRY_TIMEOUT_MS="$(printf '%s' "$compare_json" | jq -r '.timeoutMs // empty')" \
  PROVIDER_TELEMETRY_ERROR_MESSAGE="$(printf '%s' "$provider_result_json" | jq -r '.errorMessage // ""')" \
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/provider_telemetry_append.sh" \
      "$task_id" \
      "$issue_number" \
      "intake.interpretation" \
      "$(printf '%s' "$compare_json" | jq -r '.shadowProvider // "claude"')" \
      "$(printf '%s' "$compare_json" | jq -r '.shadowProvider // "claude"')" \
      "$(printf '%s' "$provider_result_json" | jq -r '.outcome')" \
      "$(printf '%s' "$provider_result_json" | jq -r '.requestId')" \
      "$(printf '%s' "$provider_result_json" | jq -r '.errorClass // empty')" >/dev/null || true
}

run_shadow_compare_if_enabled() {
  local compare_json compare_mode shadow_provider provider_result_json compare_artifact_json
  compare_json="$(resolve_provider_compare_json)"
  compare_mode="$(printf '%s' "$compare_json" | jq -r '.mode // "disabled"')"
  shadow_provider="$(printf '%s' "$compare_json" | jq -r '.shadowProvider // ""')"

  if [[ "$compare_mode" == "disabled" || "$shadow_provider" != "claude" ]]; then
    return 0
  fi

  cp "$interpretation_response_file" "$interpretation_local_response_file"

  if provider_result_json="$(
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/claude_provider_run.sh" \
      --module "intake.interpretation" \
      --request-file "$interpretation_request_file" \
      --response-file "$interpretation_claude_response_file" \
      --task-repo "$task_repo" \
      --task-id "$task_id" \
      --issue-number "$issue_number"
  )"; then
    :
  else
    provider_result_json="$(jq -nc \
      --arg taskId "$task_id" \
      --arg module "intake.interpretation" \
      '{requestId:("claude_runner_shell_failure:" + (now|tostring)),taskId:$taskId,"module":$module,provider:"claude",outcome:"error",errorClass:"runner_shell_failure",errorMessage:"claude_provider_run.sh failed"}')"
  fi

  if [[ "$(printf '%s' "$provider_result_json" | jq -r '.outcome')" != "success" || ! -f "$interpretation_claude_response_file" ]]; then
    write_shadow_error_artifact "$interpretation_claude_response_file" "$provider_result_json"
  fi

  compare_artifact_json="$(
    /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/intake_compare_artifact.sh" \
      interpretation \
      --primary-file "$interpretation_local_response_file" \
      --shadow-file "$interpretation_claude_response_file" \
      --compare-mode "$compare_mode" \
      --primary-provider "local" \
      --shadow-provider "$shadow_provider"
  )"
  printf '%s\n' "$compare_artifact_json" > "$interpretation_compare_file"
  append_shadow_compare_telemetry "$compare_json" "$provider_result_json" "$compare_artifact_json"
}

mkdir -p "$(dirname "$spec_file")"

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_capture_source_definition.sh" "$task_id" "$issue_number" >/dev/null

source_json="$(cat "$source_file")"
issue_title="$(printf '%s' "$source_json" | jq -r '.title // ""')"
issue_body="$(printf '%s' "$source_json" | jq -r '.body // ""')"
reply_text="$(printf '%s' "$source_json" | jq -r '.replyText // ""')"
source_hash="$(printf '%s' "$source_json" | jq -r '.sourceHash // ""')"
combined_text="$(printf '%s\n%s\n%s' "$issue_title" "$issue_body" "$reply_text")"
combined_body="$(printf '%s\n%s' "$issue_body" "$reply_text")"
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
done < <(task_intake_extract_expected_change_lines "$combined_body" || true) \
  | jq -R . | jq -s '.' > /tmp/task_standardize_expected_change.json
expected_change_json="$(cat /tmp/task_standardize_expected_change.json)"
rm -f /tmp/task_standardize_expected_change.json

notes_json='[]'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done < <(task_intake_extract_notes_lines "$combined_body" || true) \
  | jq -R . | jq -s '.' > /tmp/task_standardize_notes.json
notes_json="$(cat /tmp/task_standardize_notes.json)"
rm -f /tmp/task_standardize_notes.json

check_commands_json='[]'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line"
done < <(micro_profile_extract_check_commands "$combined_body" || true) \
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

repo_hints_json='[]'
if printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]' | rg -q '(андроид|android|клавиатур|keyboard|пробел|space|kiosk|lock task|device owner)'; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done < <(
    {
      [[ -d "${task_repo}/app/planka_quick_test_app" ]] && printf '%s\n' 'Android shell project exists under app/planka_quick_test_app.'
      [[ -f "${task_repo}/app/planka_quick_test_app/app/src/main/assets/index.html" ]] && printf '%s\n' 'Android shell web UI asset lives at app/planka_quick_test_app/app/src/main/assets/index.html.'
      [[ -f "${task_repo}/app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/MainActivity.kt" ]] && printf '%s\n' 'Android shell native activity lives at app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/MainActivity.kt.'
      [[ -f "${task_repo}/app/planka_quick_test_app/app/src/main/AndroidManifest.xml" ]] && printf '%s\n' 'Android shell manifest lives at app/planka_quick_test_app/app/src/main/AndroidManifest.xml.'
      [[ -d "${task_repo}/app/planka_kiosk_test_dpc" ]] && printf '%s\n' 'A separate Android test DPC project exists under app/planka_kiosk_test_dpc.'
    } | awk '!seen[$0]++'
  ) | jq -R . | jq -s '.' > /tmp/task_standardize_repo_hints.json
  repo_hints_json="$(cat /tmp/task_standardize_repo_hints.json)"
  rm -f /tmp/task_standardize_repo_hints.json
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
  --argjson repoHints "$repo_hints_json" \
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
      profileName:$profileName,
      repoHints:$repoHints
    }
  }' > "$spec_file"

if [[ -n "$output_file" ]]; then
  cp "$spec_file" "$output_file"
fi

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/intake_contract_artifact.sh" \
  interpretation-request \
  --source-file "$source_file" \
  --spec-file "$spec_file" > "$interpretation_request_file"

/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/intake_contract_artifact.sh" \
  interpretation-response \
  --spec-file "$spec_file" > "$interpretation_response_file"

run_shadow_compare_if_enabled

echo "STANDARDIZED_TASK_SPEC_READY=1"
echo "STANDARDIZED_TASK_SPEC_FILE=${spec_file}"
echo "INTAKE_INTERPRETATION_REQUEST_FILE=${interpretation_request_file}"
echo "INTAKE_INTERPRETATION_RESPONSE_FILE=${interpretation_response_file}"
echo "INTAKE_INTERPRETATION_LOCAL_RESPONSE_FILE=${interpretation_local_response_file}"
echo "INTAKE_INTERPRETATION_CLAUDE_RESPONSE_FILE=${interpretation_claude_response_file}"
echo "INTAKE_INTERPRETATION_COMPARE_FILE=${interpretation_compare_file}"
cat "$spec_file"
