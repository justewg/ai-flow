#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <rc> <started-at> <finished-at> <termination-reason> <provider-error-class> <detached>"
  exit 1
fi

task_id="$1"
issue_number="$2"
rc="$3"
started_at="$4"
finished_at="$5"
termination_reason="$6"
provider_error_class="$7"
detached="$8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
mkdir -p "$CODEX_DIR"

LEDGER_FILE="${CODEX_DIR}/execution_ledger.jsonl"
SUMMARY_FILE="${CODEX_DIR}/execution_summary.json"
MODE="$(/bin/bash "${SCRIPT_DIR}/containment_mode.sh" get --raw 2>/dev/null || printf 'AUTO')"

jq -nc \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg task "$task_id" \
  --arg issue "$issue_number" \
  --arg rc "$rc" \
  --arg started "$started_at" \
  --arg finished "$finished_at" \
  --arg term "$termination_reason" \
  --arg provider "$provider_error_class" \
  --arg detached "$detached" \
  --arg mode "$MODE" \
  '{
    ts:$ts,
    taskId:$task,
    issueNumber:$issue,
    rc:$rc,
    startedAt:$started,
    finishedAt:$finished,
    terminationReason:$term,
    providerErrorClass:$provider,
    detached:($detached == "1"),
    controlMode:$mode
  }' >> "$LEDGER_FILE"

tmp_file="$(mktemp "${CODEX_DIR}/execution_summary.XXXXXX")"
if [[ -s "$SUMMARY_FILE" ]]; then
  jq \
    --arg task "$task_id" \
    --arg issue "$issue_number" \
    --arg rc "$rc" \
    --arg started "$started_at" \
    --arg finished "$finished_at" \
    --arg term "$termination_reason" \
    --arg provider "$provider_error_class" \
    '
      .[$task] = {
        count: ((.[$task].count // 0) + 1),
        issueNumber: $issue,
        lastRc: $rc,
        lastStartedAt: $started,
        lastFinishedAt: $finished,
        lastTerminationReason: $term,
        lastProviderErrorClass: $provider
      }
    ' "$SUMMARY_FILE" > "$tmp_file"
else
  jq -nc \
    --arg task "$task_id" \
    --arg issue "$issue_number" \
    --arg rc "$rc" \
    --arg started "$started_at" \
    --arg finished "$finished_at" \
    --arg term "$termination_reason" \
    --arg provider "$provider_error_class" \
    '{
      ($task): {
        count: 1,
        issueNumber: $issue,
        lastRc: $rc,
        lastStartedAt: $started,
        lastFinishedAt: $finished,
        lastTerminationReason: $term,
        lastProviderErrorClass: $provider
      }
    }' > "$tmp_file"
fi
mv "$tmp_file" "$SUMMARY_FILE"

echo "EXECUTION_RECORDED=1"
echo "EXECUTION_TASK_ID=${task_id}"
echo "EXECUTION_RC=${rc}"
