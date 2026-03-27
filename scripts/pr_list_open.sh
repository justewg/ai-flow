#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_flow_config

pr_base_branch="${FLOW_PR_BASE_BRANCH:-$FLOW_BASE_BRANCH}"
pr_head_branch="${FLOW_PR_HEAD_BRANCH:-$FLOW_HEAD_BRANCH}"

gh pr list \
  --repo "$FLOW_GITHUB_REPO" \
  --state open \
  --base "$pr_base_branch" \
  --head "$pr_head_branch" \
  --json number,url,title \
  --jq '.'
