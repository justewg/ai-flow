#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/scripts/codex/env/resolve_config.sh"
codex_resolve_flow_config

gh pr list \
  --repo "$FLOW_GITHUB_REPO" \
  --state open \
  --base "$FLOW_BASE_BRANCH" \
  --head "$FLOW_HEAD_BRANCH" \
  --json number,url,title \
  --jq '.'
