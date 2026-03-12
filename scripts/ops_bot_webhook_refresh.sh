#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${CODEX_SHARED_SCRIPTS_DIR}/ops_bot_webhook_register.sh" refresh
