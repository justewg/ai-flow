#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <type> <message...>"
  exit 1
fi

event_type="$1"
shift
message="$*"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
mkdir -p "$CODEX_DIR"

LEDGER_FILE="${CODEX_DIR}/incident_ledger.jsonl"
MODE="$(/bin/bash "${SCRIPT_DIR}/containment_mode.sh" get --raw 2>/dev/null || printf 'AUTO')"

jq -nc \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg type "$event_type" \
  --arg mode "$MODE" \
  --arg msg "$message" \
  '{ts:$ts,type:$type,mode:$mode,message:$msg}' >> "$LEDGER_FILE"

echo "INCIDENT_APPENDED=1"
echo "INCIDENT_TYPE=${event_type}"
