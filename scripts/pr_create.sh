#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <title-file> <body-file>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_flow_config

title_file="$1"
body_file="$2"
pr_base_branch="${FLOW_PR_BASE_BRANCH:-$FLOW_BASE_BRANCH}"
pr_head_branch="${FLOW_PR_HEAD_BRANCH:-$FLOW_HEAD_BRANCH}"

if [[ ! -f "$title_file" ]]; then
  echo "Title file not found: $title_file"
  exit 1
fi

if [[ ! -f "$body_file" ]]; then
  echo "Body file not found: $body_file"
  exit 1
fi

title="$(<"$title_file")"
body="$(<"$body_file")"

gh pr create \
  --repo "$FLOW_GITHUB_REPO" \
  --base "$pr_base_branch" \
  --head "$pr_head_branch" \
  --title "$title" \
  --body "$body"
