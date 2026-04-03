#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env/bootstrap.sh"

NODE_BIN="${NODE_BIN:-node}"
CODEX_DIR="$(codex_export_state_dir)"
LEDGER_FILE="${CODEX_DIR}/provider_telemetry.jsonl"
PROVIDER_HEALTH_FILE="${CODEX_DIR}/claude_provider_health.json"

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/provider_rollout_gate.js" \
  --ledger-file "$LEDGER_FILE" \
  --provider-health-file "$PROVIDER_HEALTH_FILE" \
  "$@"
