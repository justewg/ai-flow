#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <pr-number> <title-file> <body-file>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./env/resolve_config.sh
source "${ROOT_DIR}/.flow/scripts/env/resolve_config.sh"
codex_resolve_flow_config

pr_number="$1"
title_file="$2"
body_file="$3"

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

gh pr edit "$pr_number" \
  --repo "$FLOW_GITHUB_REPO" \
  --title "$title" \
  --body "$body"
