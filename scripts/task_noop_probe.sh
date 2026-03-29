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
# shellcheck source=./task_intake_lib.sh
source "${SCRIPT_DIR}/task_intake_lib.sh"

state_dir="$(codex_resolve_state_dir)"
profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
task_repo="$(task_worktree_repo_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
if [[ ! -d "$task_repo/.git" && ! -f "$task_repo/.git" ]]; then
  task_repo="${ROOT_DIR}"
fi

source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
probe_file="$(task_worktree_noop_probe_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$(dirname "$probe_file")"

if [[ ! -f "$source_file" || ! -f "$spec_file" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_interpret.sh" "$task_id" "$issue_number" >/dev/null
fi

status="inconclusive"
reason="noop_probe_not_enough_signal"
target_file=""
matched_literal=""
matched_anchor=""
attribute_count=0
anchor_count=0

source_json="$(cat "$source_file")"
spec_json="$(cat "$spec_file")"
issue_body="$(printf '%s' "$source_json" | jq -r '.body // ""')"
target_file="$(printf '%s' "$spec_json" | jq -r '.candidateTargetFiles[0] // empty')"
target_count="$(printf '%s' "$spec_json" | jq -r '(.candidateTargetFiles // []) | length')"

if [[ "$target_count" != "1" || -z "$target_file" ]]; then
  expected_change_text="$(task_intake_extract_expected_change_lines "$issue_body" || true)"
  explicit_targets=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    explicit_targets+=("$line")
  done < <(task_intake_extract_file_paths "$expected_change_text" || true)
  if (( ${#explicit_targets[@]} > 0 )); then
    target_file="${explicit_targets[0]}"
    target_count=1
  fi
fi

if [[ "$target_count" != "1" || -z "$target_file" ]]; then
  reason="noop_probe_target_file_not_single"
else
  repo_file="${task_repo}/${target_file}"
  if [[ ! -f "$repo_file" ]]; then
    reason="noop_probe_target_file_missing"
  else
    attribute_literals=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      attribute_literals+=("$line")
    done < <(task_intake_extract_attribute_literals "$issue_body" || true)

    anchor_tokens=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      anchor_tokens+=("$line")
    done < <(task_intake_extract_anchor_tokens "$issue_body" || true)

    attribute_count="${#attribute_literals[@]}"
    anchor_count="${#anchor_tokens[@]}"

    if (( attribute_count == 0 )); then
      reason="noop_probe_no_explicit_literal"
    else
      for literal in "${attribute_literals[@]}"; do
        [[ -n "$literal" ]] || continue
        if rg -Fq -- "$literal" "$repo_file"; then
          matched_literal="$literal"
          break
        fi
      done

      if [[ -z "$matched_literal" ]]; then
        reason="noop_probe_literal_not_present"
      elif (( anchor_count > 0 )); then
        for anchor in "${anchor_tokens[@]}"; do
          [[ -n "$anchor" ]] || continue
          if rg -Fq -- "$anchor" "$repo_file"; then
            matched_anchor="$anchor"
            break
          fi
        done
        if [[ -n "$matched_anchor" ]]; then
          status="satisfied"
          reason="noop_probe_literal_and_anchor_present"
        else
          reason="noop_probe_anchor_not_present"
        fi
      else
        status="satisfied"
        reason="noop_probe_literal_present"
      fi
    fi
  fi
fi

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg status "$status" \
  --arg reason "$reason" \
  --arg targetFile "$target_file" \
  --arg matchedLiteral "$matched_literal" \
  --arg matchedAnchor "$matched_anchor" \
  --arg sourceDefinitionFile "$source_file" \
  --arg standardizedTaskSpecFile "$spec_file" \
  --arg checkedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --argjson attributeLiteralCount "$attribute_count" \
  --argjson anchorTokenCount "$anchor_count" \
  '{
    kind:"noop_probe",
    taskId:$taskId,
    issueNumber:$issueNumber,
    status:$status,
    reason:$reason,
    targetFile:$targetFile,
    matchedLiteral:$matchedLiteral,
    matchedAnchor:$matchedAnchor,
    attributeLiteralCount:$attributeLiteralCount,
    anchorTokenCount:$anchorTokenCount,
    sourceDefinitionFile:$sourceDefinitionFile,
    standardizedTaskSpecFile:$standardizedTaskSpecFile,
    checkedAt:$checkedAt
  }' > "$probe_file"

if [[ -n "$output_file" && "$output_file" != "$probe_file" ]]; then
  cp "$probe_file" "$output_file"
fi

echo "TASK_NOOP_PROBE_STATUS=${status}"
echo "TASK_NOOP_PROBE_REASON=${reason}"
[[ -n "$target_file" ]] && echo "TASK_NOOP_PROBE_TARGET_FILE=${target_file}"
[[ -n "$matched_literal" ]] && echo "TASK_NOOP_PROBE_MATCHED_LITERAL=${matched_literal}"
[[ -n "$matched_anchor" ]] && echo "TASK_NOOP_PROBE_MATCHED_ANCHOR=${matched_anchor}"
echo "TASK_NOOP_PROBE_FILE=${probe_file}"
cat "$probe_file"
