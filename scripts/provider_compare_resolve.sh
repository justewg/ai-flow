#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_BIN="${NODE_BIN:-node}"

exec "$NODE_BIN" "${SCRIPT_DIR}/../runtime-v2/bin/provider_compare.js" "$@"
