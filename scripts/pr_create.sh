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
  --base "$FLOW_BASE_BRANCH" \
  --head "$FLOW_HEAD_BRANCH" \
  --title "$title" \
  --body "$body"
