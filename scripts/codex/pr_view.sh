#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pr-number>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/scripts/codex/env/resolve_config.sh"
codex_resolve_flow_config

pr_number="$1"

gh pr view "$pr_number" \
  --repo "$FLOW_GITHUB_REPO" \
  --json number,state,url,title,headRefName,baseRefName \
  --jq '.'
