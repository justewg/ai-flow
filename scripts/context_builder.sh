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
execution_dir="$(micro_profile_state_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
context_cache_file="$(task_worktree_context_cache_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
prompt_input_file="$(task_worktree_micro_prompt_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
profile_file="$(task_worktree_execution_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
intake_profile_file="$(task_worktree_intake_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"

mkdir -p "$execution_dir"

if [[ ! -f "$spec_file" || ! -f "$source_file" || ! -f "$intake_profile_file" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/task_interpret.sh" "$task_id" "$issue_number" >/dev/null
fi

source_json="$(cat "$source_file")"
spec_json="$(cat "$spec_file")"
intake_profile_json='{}'
[[ -f "$intake_profile_file" ]] && intake_profile_json="$(cat "$intake_profile_file")"
issue_title="$(printf '%s' "$source_json" | jq -r '.title // ""')"
issue_body="$(printf '%s' "$source_json" | jq -r '.body // ""')"
task_spec_summary="$(
  jq -r '
    [
      .interpretedIntent // "",
      (if (.expectedChange // []) | length > 0 then "Expected change:\n- " + ((.expectedChange // []) | join("\n- ")) else "" end),
      (if (.notes // []) | length > 0 then "Notes:\n- " + ((.notes // []) | join("\n- ")) else "" end)
    ] | map(select(length > 0)) | join("\n\n")
  ' <<<"$spec_json"
)"
task_spec_summary="$(printf '%s' "$task_spec_summary" | head -c 2400)"

target_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  target_files+=("$line")
done < <(printf '%s' "$spec_json" | jq -r '.candidateTargetFiles[]? // empty')

check_commands=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  check_commands+=("$line")
done < <(printf '%s' "$spec_json" | jq -r '.checks[]? // empty')

target_files_json='[]'
if (( ${#target_files[@]} > 0 )); then
  target_files_json="$(
    for path in "${target_files[@]}"; do
      printf '%s\n' "$path"
    done | jq -R . | jq -s '.'
  )"
fi

check_commands_json='[]'
if (( ${#check_commands[@]} > 0 )); then
  check_commands_json="$(
    for cmd in "${check_commands[@]}"; do
      printf '%s\n' "$cmd"
    done | jq -R . | jq -s '.'
  )"
fi

file_contexts_json="$(
  if (( ${#target_files[@]} == 0 )); then
    jq -nc '[]'
  else
    for path in "${target_files[@]}"; do
      micro_profile_file_context_json "$task_repo" "$path" "$task_spec_summary"
    done | jq -s '.'
  fi
)"

profile_json='{}'
if [[ -f "$profile_file" ]]; then
  profile_json="$(cat "$profile_file")"
fi

jq -nc \
  --arg taskId "$task_id" \
  --arg issueNumber "$issue_number" \
  --arg issueTitle "$issue_title" \
  --arg issueBody "$issue_body" \
  --arg issueSummary "$task_spec_summary" \
  --argjson sourceDefinition "$source_json" \
  --argjson standardizedTaskSpec "$spec_json" \
  --argjson intakeProfile "$intake_profile_json" \
  --argjson profile "$profile_json" \
  --argjson targetFiles "$target_files_json" \
  --argjson fileContexts "$file_contexts_json" \
  --argjson checkCommands "$check_commands_json" \
  '{
    taskId:$taskId,
    issueNumber:$issueNumber,
    issueTitle:$issueTitle,
    issueBody:$issueBody,
    issueSummary:$issueSummary,
    sourceDefinition:$sourceDefinition,
    standardizedTaskSpec:$standardizedTaskSpec,
    intakeProfile:$intakeProfile,
    profile:$profile,
    targetFiles:$targetFiles,
    fileContexts:$fileContexts,
    checkCommands:$checkCommands,
    policy:{
      contextBuilderIsCanonical:true,
      discoveryReadsAllowed:false,
      allowedVerificationOnly:true,
      maxLlmCalls:2
    }
  }' > "$context_cache_file"

{
  printf '%s\n' 'Ты автономный executor разработки для репозитория PLANKA.'
  printf '\n'
  printf '%s\n' 'Рабочий профиль: micro-task.'
  printf '%s\n' 'Контекст файлов уже собран deterministic-builder и является единственным допустимым file-context.'
  printf '%s\n' 'Запрещено: discovery по репозиторию, повторные чтения файлов, grep по toolkit, чтение task_finalize.sh и других служебных flow-скриптов.'
  printf '%s\n' 'Разрешено: внести правки в target files и выполнить только whitelist verification команды из списка проверок.'
  printf '\n'
  printf '%s\n' "Task ID: ${task_id}"
  printf '%s\n' "Issue: #${issue_number}"
  printf '\n'
  printf '%s\n' 'Standardized task spec:'
  printf '%s\n' "Profile decision: $(printf '%s' "$spec_json" | jq -r '.profileDecision // "standard"')"
  printf '%s\n' "Confidence: $(printf '%s' "$spec_json" | jq -r '.confidence.label // "unknown"') ($(printf '%s' "$spec_json" | jq -r '(.confidence.score // 0) | tostring'))"
  printf '\n'
  printf '%s\n' 'Interpreted intent and expected change:'
  printf '%s\n' "$task_spec_summary"
  printf '\n'
  printf '%s\n' 'Target files:'
  if (( ${#target_files[@]} == 0 )); then
    printf '%s\n' '- (target files not inferred; do not expand scope)'
  else
    printf '%s\n' "${target_files[@]}" | sed 's/^/- /'
  fi
  printf '\n'
  printf '%s\n' 'File context:'
  printf '%s\n' "$file_contexts_json" | jq -r '.[] | "FILE: \(.path)\n\(.excerpt)\n"' || true
  printf '\n'
  printf '%s\n' 'Verification commands:'
  if (( ${#check_commands[@]} == 0 )); then
    printf '%s\n' '- (none declared)'
  else
    printf '%s\n' "${check_commands[@]}" | sed 's/^/- /'
  fi
  printf '\n'
  printf '%s\n' 'Source Definition хранится отдельно как audit source и не является execution contract.'
  printf '\n'
  printf '%s\n' 'Сделай только изменения по задаче. После правок выполни проверки и остановись. Не генерируй commit/PR metadata вручную.'
} > "$prompt_input_file"

if [[ -n "$output_file" ]]; then
  cp "$prompt_input_file" "$output_file"
fi

echo "CONTEXT_BUILDER_READY=1"
echo "CONTEXT_CACHE_FILE=${context_cache_file}"
echo "MICRO_PROMPT_INPUT_FILE=${prompt_input_file}"
