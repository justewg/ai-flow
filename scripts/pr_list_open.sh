#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_flow_config

gh pr list \
  --repo "$FLOW_GITHUB_REPO" \
  --state open \
  --base "$FLOW_BASE_BRANCH" \
  --head "$FLOW_HEAD_BRANCH" \
  --json number,url,title \
  --jq '.'
