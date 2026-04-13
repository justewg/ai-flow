#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: provider_corpus_run.sh [options]

Options:
  --issues <list>              Space/comma/newline separated issue numbers.
  --issues-file <path>         File with one issue number per line.
  --state-dir <path>           State dir for this corpus run.
  --module <name>              Module to summarize. Default: intake.interpretation.
  --shadow-provider <name>     Shadow provider for rollout gate. Default: claude.
  --min-samples <n>            Gate minimum sample count. Default: number of issues.
  --ask-kind <question|blocker> Default ask-human kind when no fixture overrides it.
  --ask-message <text>         Default ask-human message when no fixture overrides it.
  --ask-message-file <path>    File with default ask-human message.
  --ask-fixtures-file <path>   JSON/JSONL records: {issueNumber,kind,message}.
  --module execution.micro     Build execution prompt/route corpus only; no executor/LLM run.
  --module execution.standard  Build execution prompt/route corpus only; no executor/LLM run.
  --execution-live-smoke       For execution.micro only: call Claude once with no tools/edits and record structured readiness.
  --retry-transient <n>        Retries for transient shadow errors. Default: 2.
  --retry-sleep-sec <n>        Base sleep before transient retry. Default: 5.
  --no-clear                   Do not clear state dir before run.
  --rerun-transient-failed     With --no-clear, run only issues whose latest shadow result is transient.
  --allow-issue-set-rewrite    With --no-clear, allow replacing existing corpus issue set.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
# shellcheck source=./task_worktree_lib.sh
source "${SCRIPT_DIR}/task_worktree_lib.sh"
NODE_BIN="${NODE_BIN:-node}"

issues_raw=""
issues_file=""
state_dir=""
module="intake.interpretation"
shadow_provider="claude"
min_samples=""
ask_kind="question"
ask_message=""
ask_message_file=""
ask_fixtures_file=""
clear_state="1"
transient_retries="${PROVIDER_CORPUS_TRANSIENT_RETRIES:-2}"
retry_sleep_sec="${PROVIDER_CORPUS_RETRY_SLEEP_SEC:-5}"
rerun_transient_failed="0"
allow_issue_set_rewrite="0"
execution_live_smoke="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues)
      [[ $# -ge 2 ]] || { echo "Missing value for --issues" >&2; exit 1; }
      issues_raw="$2"
      shift 2
      ;;
    --issues-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --issues-file" >&2; exit 1; }
      issues_file="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-dir" >&2; exit 1; }
      state_dir="$2"
      shift 2
      ;;
    --module)
      [[ $# -ge 2 ]] || { echo "Missing value for --module" >&2; exit 1; }
      module="$2"
      shift 2
      ;;
    --shadow-provider)
      [[ $# -ge 2 ]] || { echo "Missing value for --shadow-provider" >&2; exit 1; }
      shadow_provider="$2"
      shift 2
      ;;
    --min-samples)
      [[ $# -ge 2 ]] || { echo "Missing value for --min-samples" >&2; exit 1; }
      min_samples="$2"
      shift 2
      ;;
    --ask-kind)
      [[ $# -ge 2 ]] || { echo "Missing value for --ask-kind" >&2; exit 1; }
      ask_kind="$2"
      shift 2
      ;;
    --ask-message)
      [[ $# -ge 2 ]] || { echo "Missing value for --ask-message" >&2; exit 1; }
      ask_message="$2"
      shift 2
      ;;
    --ask-message-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --ask-message-file" >&2; exit 1; }
      ask_message_file="$2"
      shift 2
      ;;
    --ask-fixtures-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --ask-fixtures-file" >&2; exit 1; }
      ask_fixtures_file="$2"
      shift 2
      ;;
    --retry-transient)
      [[ $# -ge 2 ]] || { echo "Missing value for --retry-transient" >&2; exit 1; }
      transient_retries="$2"
      shift 2
      ;;
    --retry-sleep-sec)
      [[ $# -ge 2 ]] || { echo "Missing value for --retry-sleep-sec" >&2; exit 1; }
      retry_sleep_sec="$2"
      shift 2
      ;;
    --no-clear)
      clear_state="0"
      shift
      ;;
    --rerun-transient-failed)
      rerun_transient_failed="1"
      clear_state="0"
      shift
      ;;
    --allow-issue-set-rewrite)
      allow_issue_set_rewrite="1"
      shift
      ;;
    --execution-live-smoke)
      execution_live_smoke="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$issues_file" ]]; then
  [[ -r "$issues_file" ]] || { echo "Issues file is not readable: $issues_file" >&2; exit 1; }
  issues_raw="${issues_raw}"$'\n'"$(grep -Ev '^[[:space:]]*(#|$)' "$issues_file" || true)"
fi

issues=()
while IFS= read -r issue_number; do
  [[ -n "$issue_number" ]] || continue
  issues+=("$issue_number")
done < <(
  printf '%s\n' "$issues_raw" \
    | tr ',;' '\n\n' \
    | tr ' ' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed '/^$/d' \
    | awk '!seen[$0]++'
)

if (( ${#issues[@]} == 0 )); then
  echo "No issues provided. Use --issues or --issues-file." >&2
  exit 1
fi

is_execution_plan_module() {
  case "${1:-}" in
    execution.micro|execution.standard) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "$module" != "intake.interpretation" && "$module" != "intake.ask_human" ]] && ! is_execution_plan_module "$module"; then
  echo "Unsupported corpus module for this runner: $module" >&2
  exit 1
fi
if [[ "$execution_live_smoke" == "1" && "$module" != "execution.micro" ]]; then
  echo "--execution-live-smoke is only supported for execution.micro" >&2
  exit 1
fi
if [[ "$execution_live_smoke" == "1" && "$shadow_provider" != "claude" ]]; then
  echo "--execution-live-smoke currently requires --shadow-provider claude" >&2
  exit 1
fi

ask_kind="$(printf '%s' "$ask_kind" | tr '[:upper:]' '[:lower:]')"
if [[ "$ask_kind" != "question" && "$ask_kind" != "blocker" ]]; then
  echo "Invalid --ask-kind: $ask_kind (expected question|blocker)" >&2
  exit 1
fi
if [[ -n "$ask_message_file" ]]; then
  [[ -r "$ask_message_file" ]] || { echo "Ask message file is not readable: $ask_message_file" >&2; exit 1; }
  ask_message="$(<"$ask_message_file")"
fi
if [[ -n "$ask_fixtures_file" ]]; then
  [[ -r "$ask_fixtures_file" ]] || { echo "Ask fixtures file is not readable: $ask_fixtures_file" >&2; exit 1; }
  fixtures_validation_json="$(
    jq -c -s '
      [ .[] | if type == "array" then .[] else . end ] as $items
      | {
          count: ($items | length),
          invalidCount: ([
            $items[]
            | select(
                (type != "object")
                or (((.issueNumber // "") | tostring) == "" and ((.taskId // "") | tostring) == "")
                or ((.message // null) | type != "string")
                or (((.kind // "question") | tostring | ascii_downcase) as $kind | ($kind != "question" and $kind != "blocker"))
              )
          ] | length)
        }
    ' "$ask_fixtures_file"
  )" || {
    echo "Ask fixtures file is not valid JSON/JSONL: $ask_fixtures_file" >&2
    exit 1
  }
  fixtures_count="$(printf '%s' "$fixtures_validation_json" | jq -r '.count')"
  fixtures_invalid_count="$(printf '%s' "$fixtures_validation_json" | jq -r '.invalidCount')"
  if (( fixtures_count == 0 || fixtures_invalid_count > 0 )); then
    echo "Ask fixtures file has invalid records: $ask_fixtures_file" >&2
    echo "ASK_FIXTURES_COUNT=${fixtures_count}" >&2
    echo "ASK_FIXTURES_INVALID_COUNT=${fixtures_invalid_count}" >&2
    exit 1
  fi
fi

if [[ -z "$state_dir" ]]; then
  state_dir="$(codex_resolve_state_dir)/provider-corpus/$(date -u '+%Y%m%dT%H%M%SZ')"
fi

if [[ -z "$min_samples" ]]; then
  min_samples="${#issues[@]}"
fi
corpus_issues=("${issues[@]}")
run_issues=("${issues[@]}")

if ! [[ "$min_samples" =~ ^[0-9]+$ ]] || (( min_samples < 1 )); then
  echo "Invalid --min-samples: $min_samples" >&2
  exit 1
fi
if ! [[ "$transient_retries" =~ ^[0-9]+$ ]]; then
  echo "Invalid --retry-transient: $transient_retries" >&2
  exit 1
fi
if ! [[ "$retry_sleep_sec" =~ ^[0-9]+$ ]]; then
  echo "Invalid --retry-sleep-sec: $retry_sleep_sec" >&2
  exit 1
fi

if [[ "$clear_state" == "1" ]]; then
  rm -rf "$state_dir"
fi
mkdir -p "$state_dir"

export CODEX_STATE_DIR="$state_dir"
export FLOW_STATE_DIR="$state_dir"

corpus_issue_filter_json="$(
  printf '%s\n' "${corpus_issues[@]}" \
    | jq -R 'select(test("^[0-9]+$")) | "ISSUE-" + .' \
    | jq -s .
)"

summary_file="${state_dir}/provider_corpus_summary.json"
if [[ "$clear_state" == "0" && "$allow_issue_set_rewrite" != "1" && -f "$summary_file" ]]; then
  existing_issues_json="$(jq -c '(.issues // []) | map(tostring | if startswith("ISSUE-") then . else "ISSUE-" + . end) | sort' "$summary_file")"
  requested_issues_json="$(jq -c 'sort' <<<"$corpus_issue_filter_json")"
  if [[ "$existing_issues_json" != "$requested_issues_json" ]]; then
    printf 'PROVIDER_CORPUS_ISSUE_SET_MISMATCH=1\n' >&2
    printf 'PROVIDER_CORPUS_EXISTING_ISSUES=%s\n' "$existing_issues_json" >&2
    printf 'PROVIDER_CORPUS_REQUESTED_ISSUES=%s\n' "$requested_issues_json" >&2
    printf 'PROVIDER_CORPUS_ERROR=refusing to rewrite existing corpus issue set; use a new --state-dir or --allow-issue-set-rewrite\n' >&2
    exit 2
  fi
fi

if [[ "$rerun_transient_failed" == "1" ]]; then
  telemetry_file_for_filter="${state_dir}/provider_telemetry.jsonl"
  if [[ -f "$telemetry_file_for_filter" ]]; then
    existing_corpus_records_count="$(
      jq -c --argjson issues "$corpus_issue_filter_json" --arg module "$module" --arg shadowProvider "$shadow_provider" '
        select(.taskId as $taskId | $issues | index($taskId))
        | select(.module == $module and .shadowProvider == $shadowProvider and (.compareMode == "dry_run" or .compareMode == "shadow"))
      ' "$telemetry_file_for_filter" | jq -s 'length'
    )"
    if (( existing_corpus_records_count == 0 )); then
      printf 'PROVIDER_CORPUS_RERUN_NO_MATCHING_RECORDS=1\n' >&2
      printf 'PROVIDER_CORPUS_RERUN_ERROR=no previous telemetry records for requested issues in state dir\n' >&2
      exit 2
    fi
    run_issues=()
    while IFS= read -r issue_number; do
      [[ -n "$issue_number" ]] || continue
      run_issues+=("$issue_number")
    done < <(
      jq -c --argjson issues "$corpus_issue_filter_json" --arg module "$module" --arg shadowProvider "$shadow_provider" '
        select(.taskId as $taskId | $issues | index($taskId))
        | select(.module == $module and .shadowProvider == $shadowProvider and (.compareMode == "dry_run" or .compareMode == "shadow"))
      ' "$telemetry_file_for_filter" \
        | jq -s -r '
          group_by(.taskId)[]
          | sort_by(.ts // "")[-1]
          | select((.errorClass // "") as $errorClass | ["provider_unavailable","provider_rate_limited","timeout"] | index($errorClass))
          | .taskId
          | capture("^ISSUE-(?<issueNumber>[0-9]+)$").issueNumber
        '
    )
  else
    printf 'PROVIDER_CORPUS_RERUN_NO_TELEMETRY=1\n' >&2
    printf 'PROVIDER_CORPUS_RERUN_ERROR=no provider_telemetry.jsonl in state dir\n' >&2
    exit 2
  fi
fi

run_results_file="${state_dir}/provider_corpus_results.jsonl"
gate_file="${state_dir}/provider_corpus_gate.json"
gate_ledger_file="${state_dir}/provider_corpus_gate_telemetry.jsonl"
if [[ "$clear_state" == "1" ]]; then
  : > "$run_results_file"
else
  touch "$run_results_file"
fi

printf 'PROVIDER_CORPUS_STATE_DIR=%s\n' "$state_dir"
printf 'PROVIDER_CORPUS_MODULE=%s\n' "$module"
printf 'PROVIDER_CORPUS_SHADOW_PROVIDER=%s\n' "$shadow_provider"
printf 'PROVIDER_CORPUS_ISSUES=%s\n' "$(IFS=,; printf '%s' "${corpus_issues[*]}")"
run_issues_csv=""
if (( ${#run_issues[@]} > 0 )); then
  run_issues_csv="$(IFS=,; printf '%s' "${run_issues[*]}")"
fi
printf 'PROVIDER_CORPUS_RUN_ISSUES=%s\n' "$run_issues_csv"
printf 'PROVIDER_CORPUS_TRANSIENT_RETRIES=%s\n' "$transient_retries"
printf 'PROVIDER_CORPUS_RETRY_SLEEP_SEC=%s\n' "$retry_sleep_sec"

find_compare_file() {
  local task_id="$1"
  local issue_number="$2"
  local compare_name="intake_interpretation_compare.json"
  if [[ "$module" == "intake.ask_human" ]]; then
    compare_name="intake_ask_human_compare.json"
  elif is_execution_plan_module "$module"; then
    compare_name="execution_plan_compare.json"
  fi
  find "${state_dir}/task-worktrees" \
    -path "*-${task_id}-issue-${issue_number}/meta/execution/${compare_name}" \
    -print 2>/dev/null | sort | tail -n 1
}

shadow_error_class_for_attempt() {
  local task_id="$1"
  local issue_number="$2"
  local compare_file
  compare_file="$(find_compare_file "$task_id" "$issue_number")"
  [[ -n "$compare_file" && -f "$compare_file" ]] || return 0
  jq -r '.shadowError.errorClass // empty' "$compare_file" 2>/dev/null || true
}

compare_summary_for_attempt() {
  local task_id="$1"
  local issue_number="$2"
  local compare_file
  compare_file="$(find_compare_file "$task_id" "$issue_number")"
  [[ -n "$compare_file" && -f "$compare_file" ]] || return 0
  jq -r '.compareSummary // empty' "$compare_file" 2>/dev/null || true
}

is_transient_shadow_error() {
  case "${1:-}" in
    provider_unavailable|provider_rate_limited|timeout) return 0 ;;
    *) return 1 ;;
  esac
}

ask_fixture_json_for_issue() {
  local issue_number="$1"
  [[ -n "$ask_fixtures_file" ]] || return 0
  jq -c --arg issueNumber "$issue_number" '
    if type == "array" then .[] else . end
    | select(
        ((.issueNumber // "") | tostring) == $issueNumber
        or ((.taskId // "") == ("ISSUE-" + $issueNumber))
      )
  ' "$ask_fixtures_file" | tail -n 1
}

ask_kind_for_issue() {
  local issue_number="$1"
  local fixture_json
  local fixture_kind
  fixture_json="$(ask_fixture_json_for_issue "$issue_number")"
  if [[ -n "$fixture_json" ]]; then
    fixture_kind="$(printf '%s' "$fixture_json" | jq -r '.kind // empty' | tr '[:upper:]' '[:lower:]')"
    if [[ "$fixture_kind" == "question" || "$fixture_kind" == "blocker" ]]; then
      printf '%s' "$fixture_kind"
      return 0
    fi
  fi
  printf '%s' "$ask_kind"
}

ask_message_for_issue() {
  local task_id="$1"
  local issue_number="$2"
  local issue_kind="$3"
  local fixture_json
  local fixture_message
  fixture_json="$(ask_fixture_json_for_issue "$issue_number")"
  if [[ -n "$fixture_json" ]]; then
    fixture_message="$(printf '%s' "$fixture_json" | jq -r '.message // empty')"
    if [[ -n "$fixture_message" ]]; then
      printf '%s' "$fixture_message"
      return 0
    fi
  fi
  if [[ -n "$ask_message" ]]; then
    printf '%s' "$ask_message"
    return 0
  fi
  if [[ "$issue_kind" == "blocker" ]]; then
    printf 'Блокер: executor не может безопасно продолжить по %s без выбора следующего шага. Как действовать дальше?' "$task_id"
    return 0
  fi
  printf 'ASK_QUESTION=Выбери следующий шаг для executor по %s: продолжать реализацию, финализировать или уточнить scope?' "$task_id"
}

run_issue_once() {
  local task_id="$1"
  local issue_number="$2"
  local message_file
  local issue_kind

  if [[ "$module" == "intake.interpretation" ]]; then
    /bin/bash "${SCRIPT_DIR}/task_interpret.sh" "$task_id" "$issue_number"
    return $?
  fi
  if is_execution_plan_module "$module"; then
    run_execution_plan_once "$task_id" "$issue_number"
    return $?
  fi

  printf '%s\n' "$task_id" > "${state_dir}/daemon_active_task.txt"
  printf '%s\n' "$task_id" > "${state_dir}/project_task_id.txt"
  printf '%s\n' "$issue_number" > "${state_dir}/daemon_active_issue_number.txt"
  message_file="$(mktemp "${state_dir}/provider_corpus_ask_message.XXXXXX")"
  issue_kind="$(ask_kind_for_issue "$issue_number")"
  ask_message_for_issue "$task_id" "$issue_number" "$issue_kind" > "$message_file"
  TASK_ASK_COMPARE_ONLY=1 /bin/bash "${SCRIPT_DIR}/task_ask.sh" "$issue_kind" "$message_file"
  local rc=$?
  rm -f "$message_file"
  return "$rc"
}

run_execution_plan_once() {
  local task_id="$1"
  local issue_number="$2"
  local profile_name execution_dir prompt_file source_file spec_file intake_profile_file
  local route_json route_file local_file shadow_file compare_file request_id
  local profile_decision prompt_bytes prompt_sha256 started_epoch finished_epoch latency_ms
  local requested_provider effective_provider timeout_ms budget_key decision_reason
  local candidate_target_files_json

  profile_name="$(codex_resolve_project_profile_name 2>/dev/null || printf '%s' "${PROJECT_PROFILE:-default}")"
  execution_dir="$(task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile_name")"
  source_file="$(task_worktree_source_definition_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
  spec_file="$(task_worktree_standardized_spec_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
  intake_profile_file="$(task_worktree_intake_profile_file "$task_id" "$issue_number" "$state_dir" "$profile_name")"
  prompt_file="${execution_dir}/executor_prompt.plan.txt"
  route_file="${execution_dir}/execution_plan_route.${shadow_provider}.json"
  local_file="${execution_dir}/execution_plan.local.json"
  shadow_file="${execution_dir}/execution_plan.${shadow_provider}.json"
  compare_file="${execution_dir}/execution_plan_compare.json"
  request_id="execution.plan:${module}:${task_id}:$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  mkdir -p "$execution_dir"
  started_epoch="$(date +%s)"

  if [[ ! -f "$spec_file" || ! -f "$source_file" || ! -f "$intake_profile_file" ]]; then
    if ! /bin/bash "${SCRIPT_DIR}/task_interpret.sh" "$task_id" "$issue_number" >/dev/null; then
      echo "EXECUTION_PLAN_TASK_INTERPRET_FAILED=1" >&2
      return 1
    fi
  fi
  if ! /bin/bash "${SCRIPT_DIR}/executor_build_prompt.sh" "$task_id" "$issue_number" "$prompt_file" >/dev/null; then
    echo "EXECUTION_PLAN_BUILD_PROMPT_FAILED=1" >&2
    return 1
  fi
  if [[ ! -s "$prompt_file" ]]; then
    echo "EXECUTION_PLAN_PROMPT_MISSING=1" >&2
    echo "EXECUTION_PLAN_PROMPT_FILE=${prompt_file}" >&2
    return 1
  fi

  prompt_bytes="$(wc -c < "$prompt_file" | tr -d '[:space:]')"
  prompt_sha256="$(shasum -a 256 "$prompt_file" | awk '{print $1}')"
  profile_decision="$(jq -r '.profileDecision // .profile // "standard"' "$intake_profile_file" 2>/dev/null || printf 'standard')"
  candidate_target_files_json="$(jq -c '.candidateTargetFiles // []' "$spec_file" 2>/dev/null || printf '[]')"

  if ! route_json="$(
    /bin/bash "${SCRIPT_DIR}/provider_route_resolve.sh" \
      --module "$module" \
      --task-id "$task_id" \
      --issue-number "$issue_number" \
      --preferred-provider "$shadow_provider"
  )"; then
    echo "EXECUTION_PLAN_ROUTE_RESOLVE_FAILED=1" >&2
    return 1
  fi
  printf '%s\n' "$route_json" > "$route_file"
  requested_provider="$(printf '%s' "$route_json" | jq -r '.requestedProvider')"
  effective_provider="$(printf '%s' "$route_json" | jq -r '.effectiveProvider')"
  timeout_ms="$(printf '%s' "$route_json" | jq -r '.timeoutMs // empty')"
  budget_key="$(printf '%s' "$route_json" | jq -r '.budgetKey // empty')"
  decision_reason="$(printf '%s' "$route_json" | jq -r '.decisionReason // "configured_provider"')"

  jq -n \
    --arg taskId "$task_id" \
    --argjson issueNumber "$issue_number" \
    --arg module "$module" \
    --arg provider "local" \
    --arg promptFile "$prompt_file" \
    --argjson promptBytes "$prompt_bytes" \
    --arg promptSha256 "$prompt_sha256" \
    --arg profileDecision "$profile_decision" \
    --argjson candidateTargetFiles "$candidate_target_files_json" \
    '{kind:"execution_plan",taskId:$taskId,issueNumber:$issueNumber,module:$module,provider:$provider,promptFile:$promptFile,promptBytes:$promptBytes,promptSha256:$promptSha256,profileDecision:$profileDecision,candidateTargetFiles:$candidateTargetFiles}' \
    > "$local_file"

  jq -n \
    --arg taskId "$task_id" \
    --argjson issueNumber "$issue_number" \
    --arg module "$module" \
    --arg provider "$effective_provider" \
    --arg promptFile "$prompt_file" \
    --argjson promptBytes "$prompt_bytes" \
    --arg promptSha256 "$prompt_sha256" \
    --arg profileDecision "$profile_decision" \
    --argjson candidateTargetFiles "$candidate_target_files_json" \
    --argjson route "$route_json" \
    '{kind:"execution_plan",taskId:$taskId,issueNumber:$issueNumber,module:$module,provider:$provider,promptFile:$promptFile,promptBytes:$promptBytes,promptSha256:$promptSha256,profileDecision:$profileDecision,candidateTargetFiles:$candidateTargetFiles,route:$route}' \
    > "$shadow_file"

  jq -n \
    --arg module "$module" \
    --arg primaryProvider "local" \
    --arg shadowProvider "$effective_provider" \
    --arg profileDecision "$profile_decision" \
    --arg promptSha256 "$prompt_sha256" \
    --argjson promptBytes "$prompt_bytes" \
    --argjson route "$route_json" \
    '{
      module:$module,
      compareMode:"dry_run",
      primaryProvider:$primaryProvider,
      shadowProvider:$shadowProvider,
      schemaValidPrimary:true,
      schemaValidShadow:true,
      executionPlanReady:true,
      profileDecision:$profileDecision,
      promptBytes:$promptBytes,
      promptSha256:$promptSha256,
      route:$route,
      compareSummary:"execution_plan_ready",
      publishDecision:false
    }' > "$compare_file"

  finished_epoch="$(date +%s)"
  latency_ms="$(( (finished_epoch - started_epoch) * 1000 ))"
  PROVIDER_TELEMETRY_LATENCY_MS="$latency_ms" \
  PROVIDER_TELEMETRY_COMPARE_MODE="dry_run" \
  PROVIDER_TELEMETRY_PRIMARY_PROVIDER="local" \
  PROVIDER_TELEMETRY_SHADOW_PROVIDER="$effective_provider" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_PRIMARY="true" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_SHADOW="true" \
  PROVIDER_TELEMETRY_COMPARE_SUMMARY="execution_plan_ready" \
  PROVIDER_TELEMETRY_PUBLISH_DECISION=0 \
  PROVIDER_TELEMETRY_DECISION_REASON="$decision_reason" \
  PROVIDER_TELEMETRY_TIMEOUT_MS="$timeout_ms" \
  PROVIDER_TELEMETRY_BUDGET_KEY="$budget_key" \
    /bin/bash "${SCRIPT_DIR}/provider_telemetry_append.sh" \
      "$task_id" \
      "$issue_number" \
      "$module" \
      "$requested_provider" \
      "$effective_provider" \
      "success" \
      "$request_id" >/dev/null

  printf 'EXECUTION_PLAN_READY=1\n'
  printf 'TASK_ID=%s\n' "$task_id"
  printf 'ISSUE_NUMBER=%s\n' "$issue_number"
  printf 'EXECUTION_PLAN_MODULE=%s\n' "$module"
  printf 'EXECUTION_PLAN_PROVIDER=%s\n' "$effective_provider"
  printf 'EXECUTION_PLAN_PROMPT_FILE=%s\n' "$prompt_file"
  printf 'EXECUTION_PLAN_COMPARE_FILE=%s\n' "$compare_file"

  if [[ "$execution_live_smoke" == "1" ]]; then
    run_execution_micro_live_smoke \
      "$task_id" \
      "$issue_number" \
      "$execution_dir" \
      "$prompt_file" \
      "$prompt_bytes" \
      "$prompt_sha256" \
      "$candidate_target_files_json" \
      "$effective_provider" \
      "$timeout_ms"
  fi
}

run_execution_micro_live_smoke() {
  local task_id="$1"
  local issue_number="$2"
  local execution_dir="$3"
  local prompt_file="$4"
  local prompt_bytes="$5"
  local prompt_sha256="$6"
  local candidate_target_files_json="$7"
  local effective_provider="$8"
  local timeout_ms="$9"
  local request_file response_file result_file compare_file provider_result_json
  local outcome error_class latency_ms token_usage estimated_cost request_id
  local schema_valid_shadow live_compare_summary risk_level can_proceed needs_human

  request_file="${execution_dir}/execution_micro_live_smoke_request.${effective_provider}.json"
  response_file="${execution_dir}/execution_micro_live_smoke_response.${effective_provider}.json"
  result_file="${execution_dir}/execution_micro_live_smoke_result.${effective_provider}.json"
  compare_file="${execution_dir}/execution_plan_compare.json"

  jq -n \
    --arg taskId "$task_id" \
    --argjson issueNumber "$issue_number" \
    --arg promptText "$(cat "$prompt_file")" \
    --arg promptSha256 "$prompt_sha256" \
    --argjson promptBytes "$prompt_bytes" \
    --argjson candidateTargetFiles "$candidate_target_files_json" \
    '{
      module:"execution.micro",
      input:{
        taskId:$taskId,
        issueNumber:$issueNumber,
        promptSha256:$promptSha256,
        promptBytes:$promptBytes,
        candidateTargetFiles:$candidateTargetFiles,
        liveSmokeOnly:true,
        sideEffectsAllowed:false
      },
      promptText:([
        "This is an execution.micro live smoke. Do not edit files, do not use tools, do not run shell commands, do not create commits or PRs.",
        "Inspect whether the executor prompt below is safe and actionable for a future micro execution.",
        "Return JSON only with fields: canProceed boolean, summary string, plannedFiles string[], riskLevel low|medium|high, risks string[], verification string[], needsHuman string|null, notes string[].",
        "Executor prompt SHA-256: " + $promptSha256,
        "Executor prompt:",
        $promptText
      ] | join("\n\n"))
    }' > "$request_file"

  provider_result_json="$(
    /bin/bash "${SCRIPT_DIR}/claude_provider_run.sh" \
      --module "execution.micro" \
      --request-file "$request_file" \
      --response-file "$response_file" \
      --task-id "$task_id" \
      --issue-number "$issue_number" \
      --timeout-ms "${timeout_ms:-120000}"
  )"
  printf '%s\n' "$provider_result_json" > "$result_file"

  outcome="$(printf '%s' "$provider_result_json" | jq -r '.outcome // "error"')"
  error_class="$(printf '%s' "$provider_result_json" | jq -r '.errorClass // empty')"
  latency_ms="$(printf '%s' "$provider_result_json" | jq -r '.latencyMs // empty')"
  token_usage="$(printf '%s' "$provider_result_json" | jq -r '.tokenUsage // empty')"
  estimated_cost="$(printf '%s' "$provider_result_json" | jq -r '.estimatedCost // empty')"
  request_id="$(printf '%s' "$provider_result_json" | jq -r '.requestId // empty')"
  schema_valid_shadow="false"
  live_compare_summary="execution_micro_live_smoke_error"
  risk_level=""
  can_proceed="false"
  needs_human=""

  if [[ "$outcome" == "success" && -s "$response_file" ]]; then
    schema_valid_shadow="true"
    risk_level="$(jq -r '.riskLevel // ""' "$response_file")"
    can_proceed="$(jq -r '.canProceed // false' "$response_file")"
    needs_human="$(jq -r '.needsHuman // empty' "$response_file")"
    if [[ "$can_proceed" == "true" && "$risk_level" != "high" && -z "$needs_human" ]]; then
      live_compare_summary="execution_micro_live_smoke_ready"
    else
      live_compare_summary="execution_micro_live_smoke_needs_attention"
    fi
  elif [[ -n "$error_class" ]]; then
    live_compare_summary="execution_micro_live_smoke_error:${error_class}"
  fi

  jq -n \
    --arg module "execution.micro" \
    --arg primaryProvider "local" \
    --arg shadowProvider "$effective_provider" \
    --argjson schemaValidShadow "$schema_valid_shadow" \
    --arg promptSha256 "$prompt_sha256" \
    --argjson promptBytes "$prompt_bytes" \
    --arg compareSummary "$live_compare_summary" \
    --argjson response "$(if [[ -s "$response_file" ]]; then cat "$response_file"; else printf '{}'; fi)" \
    --argjson shadowError "$(printf '%s' "$provider_result_json" | jq -c 'if .outcome == "success" then null else {errorClass:.errorClass,errorMessage:.errorMessage,requestId:.requestId,outcome:.outcome,latencyMs:.latencyMs,tokenUsage:.tokenUsage,estimatedCost:.estimatedCost} end')" \
    '{
      module:$module,
      compareMode:"dry_run",
      primaryProvider:$primaryProvider,
      shadowProvider:$shadowProvider,
      schemaValidPrimary:true,
      schemaValidShadow:$schemaValidShadow,
      executionPlanReady:true,
      executionLiveSmoke:true,
      promptBytes:$promptBytes,
      promptSha256:$promptSha256,
      shadowResponse:$response,
      shadowError:$shadowError,
      compareSummary:$compareSummary,
      publishDecision:false
    }' > "$compare_file"

  PROVIDER_TELEMETRY_LATENCY_MS="$latency_ms" \
  PROVIDER_TELEMETRY_TOKEN_USAGE="$token_usage" \
  PROVIDER_TELEMETRY_ESTIMATED_COST="$estimated_cost" \
  PROVIDER_TELEMETRY_COMPARE_MODE="dry_run" \
  PROVIDER_TELEMETRY_PRIMARY_PROVIDER="local" \
  PROVIDER_TELEMETRY_SHADOW_PROVIDER="$effective_provider" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_PRIMARY="true" \
  PROVIDER_TELEMETRY_SCHEMA_VALID_SHADOW="$schema_valid_shadow" \
  PROVIDER_TELEMETRY_COMPARE_SUMMARY="$live_compare_summary" \
  PROVIDER_TELEMETRY_PUBLISH_DECISION=0 \
  PROVIDER_TELEMETRY_DECISION_REASON="execution_micro_live_smoke" \
  PROVIDER_TELEMETRY_ERROR_MESSAGE="$(printf '%s' "$provider_result_json" | jq -r '.errorMessage // ""')" \
    /bin/bash "${SCRIPT_DIR}/provider_telemetry_append.sh" \
      "$task_id" \
      "$issue_number" \
      "execution.micro" \
      "$effective_provider" \
      "$effective_provider" \
      "$outcome" \
      "${request_id:-execution_micro_live_smoke:${task_id}}" \
      "$error_class" >/dev/null

  printf 'EXECUTION_MICRO_LIVE_SMOKE_READY=%s\n' "$([[ "$live_compare_summary" == "execution_micro_live_smoke_ready" ]] && printf '1' || printf '0')"
  printf 'EXECUTION_MICRO_LIVE_SMOKE_COMPARE_SUMMARY=%s\n' "$live_compare_summary"
  printf 'EXECUTION_MICRO_LIVE_SMOKE_RESPONSE_FILE=%s\n' "$response_file"
  printf 'EXECUTION_MICRO_LIVE_SMOKE_RESULT_FILE=%s\n' "$result_file"
}

if (( ${#run_issues[@]} > 0 )); then
  for issue_number in "${run_issues[@]}"; do
    if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
      jq -nc \
        --arg issueNumber "$issue_number" \
        '{issueNumber:$issueNumber,status:"skipped",error:"invalid_issue_number"}' >> "$run_results_file"
      continue
    fi

    task_id="ISSUE-${issue_number}"
    attempt=0
    while :; do
      attempt=$((attempt + 1))
      printf 'PROVIDER_CORPUS_RUN task=%s issue=%s attempt=%s\n' "$task_id" "$issue_number" "$attempt"
      started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      set +e
      output="$(run_issue_once "$task_id" "$issue_number" 2>&1)"
      rc=$?
      set -e
      finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf '%s\n' "$output"
      shadow_error_class="$(shadow_error_class_for_attempt "$task_id" "$issue_number")"
      compare_summary="$(compare_summary_for_attempt "$task_id" "$issue_number")"
      jq -nc \
        --arg taskId "$task_id" \
        --argjson issueNumber "$issue_number" \
        --argjson attempt "$attempt" \
        --arg startedAt "$started_at" \
        --arg finishedAt "$finished_at" \
        --argjson rc "$rc" \
        --arg shadowErrorClass "$shadow_error_class" \
        --arg compareSummary "$compare_summary" \
        --arg output "$output" \
        '{taskId:$taskId,issueNumber:$issueNumber,attempt:$attempt,startedAt:$startedAt,finishedAt:$finishedAt,rc:$rc,status:(if $rc == 0 then "ok" else "error" end),shadowErrorClass:(if $shadowErrorClass == "" then null else $shadowErrorClass end),compareSummary:(if $compareSummary == "" then null else $compareSummary end),output:$output}' \
        >> "$run_results_file"

      if (( rc != 0 )) || ! is_transient_shadow_error "$shadow_error_class" || (( attempt > transient_retries )); then
        break
      fi

      sleep_for=$(( retry_sleep_sec * attempt ))
      printf 'PROVIDER_CORPUS_TRANSIENT_RETRY task=%s issue=%s attempt=%s error=%s sleepSec=%s\n' \
        "$task_id" "$issue_number" "$attempt" "$shadow_error_class" "$sleep_for"
      sleep "$sleep_for"
    done
  done
fi

telemetry_file="${state_dir}/provider_telemetry.jsonl"
if [[ ! -f "$telemetry_file" ]]; then
  : > "$telemetry_file"
fi

jq -nc --argjson issues "$corpus_issue_filter_json" \
  '{issues:$issues}' > "${state_dir}/provider_corpus_issue_filter.json"

jq -c --slurpfile filter "${state_dir}/provider_corpus_issue_filter.json" --arg module "$module" --arg shadowProvider "$shadow_provider" '
  select(.taskId as $taskId | ($filter[0].issues // []) | index($taskId))
  | select(.module == $module and .shadowProvider == $shadowProvider and (.compareMode == "dry_run" or .compareMode == "shadow"))
' "$telemetry_file" \
  | jq -s -c 'group_by(.taskId)[] | sort_by(.ts)[-1]' > "$gate_ledger_file"
rm -f "${state_dir}/provider_corpus_issue_filter.json"

CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/provider_rollout_gate.js" \
  --ledger-file "$gate_ledger_file" \
  --provider-health-file "${state_dir}/claude_provider_health.json" \
  --module "$module" \
  --shadow-provider "$shadow_provider" \
  --min-samples "$min_samples" > "$gate_file"

corpus_issues_json="$(printf '%s\n' "${corpus_issues[@]}" | jq -R . | jq -s .)"
run_issues_json="[]"
if (( ${#run_issues[@]} > 0 )); then
  run_issues_json="$(printf '%s\n' "${run_issues[@]}" | jq -R . | jq -s .)"
fi

jq -n \
  --arg stateDir "$state_dir" \
  --arg module "$module" \
  --arg shadowProvider "$shadow_provider" \
  --argjson issues "$corpus_issues_json" \
  --argjson runIssues "$run_issues_json" \
  --argjson taskRuns "$(jq -s . "$run_results_file")" \
  --argjson gate "$(cat "$gate_file")" \
  --slurpfile telemetry "$telemetry_file" \
  --slurpfile gateTelemetry "$gate_ledger_file" \
  '{
    stateDir:$stateDir,
    module:$module,
    shadowProvider:$shadowProvider,
    issues:$issues,
    runIssues:$runIssues,
    taskRuns:$taskRuns,
    gate:$gate,
    telemetry:{
      count:($telemetry|length),
      tokenUsageTotal:($telemetry | map(.tokenUsage // 0) | add // 0),
      latencyMsTotal:($telemetry | map(.latencyMs // 0) | add // 0),
      estimatedCostTotal:($telemetry | map(.estimatedCost // 0) | add // 0),
      compareSummaryCounts:(
        reduce ($telemetry[]? | .compareSummary // "none") as $summary ({}; .[$summary] = ((.[$summary] // 0) + 1))
      )
    },
    gateTelemetry:{
      count:($gateTelemetry|length),
      tokenUsageTotal:($gateTelemetry | map(.tokenUsage // 0) | add // 0),
      latencyMsTotal:($gateTelemetry | map(.latencyMs // 0) | add // 0),
      estimatedCostTotal:($gateTelemetry | map(.estimatedCost // 0) | add // 0),
      compareSummaryCounts:(
        reduce ($gateTelemetry[]? | .compareSummary // "none") as $summary ({}; .[$summary] = ((.[$summary] // 0) + 1))
      )
    }
  }' > "$summary_file"

printf 'PROVIDER_CORPUS_RESULTS_FILE=%s\n' "$run_results_file"
printf 'PROVIDER_CORPUS_GATE_FILE=%s\n' "$gate_file"
printf 'PROVIDER_CORPUS_SUMMARY_FILE=%s\n' "$summary_file"
cat "$summary_file"
