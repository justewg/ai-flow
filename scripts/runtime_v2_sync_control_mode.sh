#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"
V2_STORE_DIR="${V2_STATE_DIR}/store"
mkdir -p "$V2_STORE_DIR"

control_json="$(node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_control_mode.js" \
  --store-dir "$V2_STORE_DIR")"
printf '%s\n' "$control_json"

desired_mode="$(printf '%s' "$control_json" | jq -r '.mode // "AUTO"')"
desired_reason="$(printf '%s' "$control_json" | jq -r '.reason // ""')"
current_mode="$(/bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" get --raw 2>/dev/null || printf 'AUTO')"

echo "RUNTIME_V2_CONTROL_MODE=$desired_mode"
echo "RUNTIME_V2_CONTROL_REASON=$desired_reason"
echo "RUNTIME_V2_CONTROL_PREVIOUS_MODE=$current_mode"

if [[ "$desired_mode" != "$current_mode" ]]; then
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/containment_mode.sh" set "$desired_mode" "$desired_reason" >/dev/null
  echo "RUNTIME_V2_CONTROL_MODE_SYNCED=1"
else
  echo "RUNTIME_V2_CONTROL_MODE_SYNCED=0"
fi
