#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
V2_STATE_DIR="${CODEX_DIR}/runtime_v2"
V2_STORE_DIR="${V2_STATE_DIR}/store"
mkdir -p "$V2_STORE_DIR"

context_json="$(node "${SCRIPT_DIR}/../runtime-v2/bin/runtime_v2_primary_context.js" \
  --store-dir "$V2_STORE_DIR")"

printf '%s\n' "$context_json"
echo "RUNTIME_V2_PRIMARY_ACTIVE_COUNT=$(printf '%s' "$context_json" | jq -r '(.active // []) | length')"
echo "RUNTIME_V2_PRIMARY_REVIEW_COUNT=$(printf '%s' "$context_json" | jq -r '(.review // []) | length')"
echo "RUNTIME_V2_PRIMARY_WAITING_COUNT=$(printf '%s' "$context_json" | jq -r '(.waiting // []) | length')"
echo "RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=$(printf '%s' "$context_json" | jq -r '(.active[0].taskId // "")')"
echo "RUNTIME_V2_PRIMARY_ACTIVE_ISSUE_NUMBER=$(printf '%s' "$context_json" | jq -r '(.active[0].issueNumber // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_TASK_ID=$(printf '%s' "$context_json" | jq -r '(.review[0].taskId // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_ISSUE_NUMBER=$(printf '%s' "$context_json" | jq -r '(.review[0].issueNumber // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_PR_NUMBER=$(printf '%s' "$context_json" | jq -r '(.review[0].prNumber // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_COMMENT_ID=$(printf '%s' "$context_json" | jq -r '(.review[0].waitCommentId // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_COMMENT_URL=$(printf '%s' "$context_json" | jq -r '(.review[0].commentUrl // "")')"
echo "RUNTIME_V2_PRIMARY_REVIEW_PENDING_POST=$(printf '%s' "$context_json" | jq -r 'if .review[0].pendingPost then "1" else "0" end')"
echo "RUNTIME_V2_PRIMARY_REVIEW_SINCE=$(printf '%s' "$context_json" | jq -r '(.review[0].waitingSince // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_TASK_ID=$(printf '%s' "$context_json" | jq -r '(.waiting[0].taskId // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_ISSUE_NUMBER=$(printf '%s' "$context_json" | jq -r '(.waiting[0].issueNumber // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_COMMENT_ID=$(printf '%s' "$context_json" | jq -r '(.waiting[0].waitCommentId // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_KIND=$(printf '%s' "$context_json" | jq -r '(.waiting[0].kind // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_COMMENT_URL=$(printf '%s' "$context_json" | jq -r '(.waiting[0].commentUrl // "")')"
echo "RUNTIME_V2_PRIMARY_WAITING_PENDING_POST=$(printf '%s' "$context_json" | jq -r 'if .waiting[0].pendingPost then "1" else "0" end')"
echo "RUNTIME_V2_PRIMARY_WAITING_SINCE=$(printf '%s' "$context_json" | jq -r '(.waiting[0].waitingSince // "")')"
