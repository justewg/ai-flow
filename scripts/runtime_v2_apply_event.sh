#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 || $# -gt 6 ]]; then
  echo "Usage: $0 <task-id> <issue-number> <event-type> <event-id> <dedup-key> [payload-json]"
  exit 1
fi

task_id="$1"
issue_number="$2"
event_type="$3"
event_id="$4"
dedup_key="$5"
payload_json="${6:-"{}"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"
V2_STORE_DIR="${V2_STATE_DIR}/store"
mkdir -p "$V2_STORE_DIR"

repo="${FLOW_GITHUB_REPO:-unknown/repo}"

if normalized_payload_json="$(printf '%s' "$payload_json" | jq -c . 2>/dev/null)"; then
  payload_json="$normalized_payload_json"
else
  payload_json="$(
    node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_normalize_payload_json.js" \
      --payload-json "$payload_json"
  )"
fi

event_json="$(node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_apply_event.js" \
  --legacy-state-dir "$CODEX_DIR" \
  --store-dir "$V2_STORE_DIR" \
  --repo "$repo" \
  --task-id "$task_id" \
  --issue-number "$issue_number" \
  --event-type "$event_type" \
  --event-id "$event_id" \
  --source "legacy_shell_bridge_v2" \
  --dedup-key "$dedup_key" \
  --payload-json "$payload_json")"

printf '%s\n' "$event_json"
echo "RUNTIME_V2_EVENT_STATUS=$(printf '%s' "$event_json" | jq -r '.status // "unknown"')"
echo "RUNTIME_V2_EVENT_REASON=$(printf '%s' "$event_json" | jq -r '.reason // ""')"
echo "RUNTIME_V2_EVENT_TASK_ID=$task_id"
echo "RUNTIME_V2_EVENT_TYPE=$event_type"
