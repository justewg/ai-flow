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

pr_base_branch="${FLOW_PR_BASE_BRANCH:-$FLOW_BASE_BRANCH}"
pr_head_branch="${FLOW_PR_HEAD_BRANCH:-$FLOW_HEAD_BRANCH}"

title_file="$1"
body_file="$2"

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

create_out="$(
  gh pr create \
    --repo "$FLOW_GITHUB_REPO" \
    --base "$pr_base_branch" \
    --head "$pr_head_branch" \
    --title "$title" \
    --body "$body" 2>&1
)" && {
  printf '%s\n' "$create_out"
  exit 0
}

create_rc=$?
if printf '%s' "$create_out" | grep -Eiq 'GraphQL: API rate limit|API rate limit already exceeded'; then
  gh api "repos/${FLOW_GITHUB_REPO}/pulls" \
    -f title="$title" \
    -f head="$pr_head_branch" \
    -f base="$pr_base_branch" \
    -f body="$body" \
    --jq '.html_url'
  exit 0
fi

printf '%s\n' "$create_out" >&2
exit "$create_rc"
