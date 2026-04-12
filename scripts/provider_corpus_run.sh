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
  --retry-transient <n>        Retries for transient shadow errors. Default: 2.
  --retry-sleep-sec <n>        Base sleep before transient retry. Default: 5.
  --no-clear                   Do not clear state dir before run.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
NODE_BIN="${NODE_BIN:-node}"

issues_raw=""
issues_file=""
state_dir=""
module="intake.interpretation"
shadow_provider="claude"
min_samples=""
clear_state="1"
transient_retries="${PROVIDER_CORPUS_TRANSIENT_RETRIES:-2}"
retry_sleep_sec="${PROVIDER_CORPUS_RETRY_SLEEP_SEC:-5}"

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

mapfile -t issues < <(
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

if [[ "$module" != "intake.interpretation" ]]; then
  echo "Unsupported corpus module for this runner: $module" >&2
  exit 1
fi

if [[ -z "$state_dir" ]]; then
  state_dir="$(codex_resolve_state_dir)/provider-corpus/$(date -u '+%Y%m%dT%H%M%SZ')"
fi

if [[ -z "$min_samples" ]]; then
  min_samples="${#issues[@]}"
fi

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

run_results_file="${state_dir}/provider_corpus_results.jsonl"
gate_file="${state_dir}/provider_corpus_gate.json"
summary_file="${state_dir}/provider_corpus_summary.json"
gate_ledger_file="${state_dir}/provider_corpus_gate_telemetry.jsonl"
: > "$run_results_file"

printf 'PROVIDER_CORPUS_STATE_DIR=%s\n' "$state_dir"
printf 'PROVIDER_CORPUS_MODULE=%s\n' "$module"
printf 'PROVIDER_CORPUS_SHADOW_PROVIDER=%s\n' "$shadow_provider"
printf 'PROVIDER_CORPUS_ISSUES=%s\n' "$(IFS=,; printf '%s' "${issues[*]}")"
printf 'PROVIDER_CORPUS_TRANSIENT_RETRIES=%s\n' "$transient_retries"
printf 'PROVIDER_CORPUS_RETRY_SLEEP_SEC=%s\n' "$retry_sleep_sec"

find_compare_file() {
  local task_id="$1"
  local issue_number="$2"
  find "${state_dir}/task-worktrees" \
    -path "*-${task_id}-issue-${issue_number}/meta/execution/intake_interpretation_compare.json" \
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

for issue_number in "${issues[@]}"; do
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
    output="$(/bin/bash "${SCRIPT_DIR}/task_interpret.sh" "$task_id" "$issue_number" 2>&1)"
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

telemetry_file="${state_dir}/provider_telemetry.jsonl"
if [[ ! -f "$telemetry_file" ]]; then
  : > "$telemetry_file"
fi

jq -nc --argjson issues "$(printf '%s\n' "${issues[@]}" | jq -R 'select(test("^[0-9]+$")) | "ISSUE-" + .' | jq -s .)" \
  '{issues:$issues}' > "${state_dir}/provider_corpus_issue_filter.json"

jq -c --slurpfile filter "${state_dir}/provider_corpus_issue_filter.json" '
  select(.taskId as $taskId | ($filter[0].issues // []) | index($taskId))
' "$telemetry_file" \
  | jq -s -c 'group_by(.taskId)[] | sort_by(.ts)[-1]' > "$gate_ledger_file"
rm -f "${state_dir}/provider_corpus_issue_filter.json"

CODEX_STATE_DIR="$state_dir" FLOW_STATE_DIR="$state_dir" "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/provider_rollout_gate.js" \
  --ledger-file "$gate_ledger_file" \
  --provider-health-file "${state_dir}/claude_provider_health.json" \
  --module "$module" \
  --shadow-provider "$shadow_provider" \
  --min-samples "$min_samples" > "$gate_file"

jq -n \
  --arg stateDir "$state_dir" \
  --arg module "$module" \
  --arg shadowProvider "$shadow_provider" \
  --argjson issues "$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)" \
  --argjson taskRuns "$(jq -s . "$run_results_file")" \
  --argjson gate "$(cat "$gate_file")" \
  --slurpfile telemetry "$telemetry_file" \
  --slurpfile gateTelemetry "$gate_ledger_file" \
  '{
    stateDir:$stateDir,
    module:$module,
    shadowProvider:$shadowProvider,
    issues:$issues,
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
