#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env/bootstrap.sh"

STATE_DIR="$(codex_resolve_state_dir)"
HEALTH_FILE="${STATE_DIR}/claude_provider_health.json"

rm -f "$HEALTH_FILE"
echo "CLAUDE_PROVIDER_HEALTH_CLEARED=1"
echo "CLAUDE_PROVIDER_HEALTH_FILE=${HEALTH_FILE}"
