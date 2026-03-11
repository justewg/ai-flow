#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${ROOT_DIR}/.flow/scripts/ops_bot_webhook_register.sh" refresh
