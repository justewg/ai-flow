#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
mkdir -p "$CODEX_DIR"

active_task_file="${CODEX_DIR}/daemon_active_task.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
project_task_file="${CODEX_DIR}/project_task_id.txt"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
review_branch_file="${CODEX_DIR}/daemon_review_branch_name.txt"
waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
waiting_task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
waiting_question_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
waiting_pending_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"
claim_epoch_file="${CODEX_DIR}/daemon_last_claim_epoch.txt"

read_int_file_or_default() {
  local file_path="${1:-}"
  local default_value="${2:-0}"
  local value=""
  if [[ -n "$file_path" && -s "$file_path" ]]; then
    value="$(tr -d '\r\n' < "$file_path" 2>/dev/null || true)"
  fi
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

context_out="$(
  /bin/bash "${CODEX_SHARED_SCRIPTS_DIR}/runtime_v2_primary_context.sh" 2>&1
)"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line"
done <<<"$context_out"

active_count="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_ACTIVE_COUNT=//p' | tail -n1)"
review_count="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_COUNT=//p' | tail -n1)"
active_task_id="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=//p' | tail -n1)"
active_issue_number="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_ACTIVE_ISSUE_NUMBER=//p' | tail -n1)"
review_task_id="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_TASK_ID=//p' | tail -n1)"
review_issue_number="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_ISSUE_NUMBER=//p' | tail -n1)"
review_pr_number="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_PR_NUMBER=//p' | tail -n1)"
review_comment_id="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_COMMENT_ID=//p' | tail -n1)"
review_comment_url="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_COMMENT_URL=//p' | tail -n1)"
review_pending_post="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_PENDING_POST=//p' | tail -n1)"
review_since="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_REVIEW_SINCE=//p' | tail -n1)"
waiting_count="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_COUNT=//p' | tail -n1)"
waiting_task_id="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_TASK_ID=//p' | tail -n1)"
waiting_issue_number="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_ISSUE_NUMBER=//p' | tail -n1)"
waiting_comment_id="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_COMMENT_ID=//p' | tail -n1)"
waiting_kind="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_KIND=//p' | tail -n1)"
waiting_comment_url="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_COMMENT_URL=//p' | tail -n1)"
waiting_pending_post="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_PENDING_POST=//p' | tail -n1)"
waiting_since="$(printf '%s\n' "$context_out" | sed -n 's/^RUNTIME_V2_PRIMARY_WAITING_SINCE=//p' | tail -n1)"

current_active_task="$(cat "$active_task_file" 2>/dev/null || true)"
current_review_task="$(cat "$review_task_file" 2>/dev/null || true)"
current_waiting_task="$(cat "$waiting_task_file" 2>/dev/null || true)"
current_waiting_kind="$(cat "$waiting_kind_file" 2>/dev/null || true)"

if [[ "$active_count" == "1" ]]; then
  printf '%s\n' "$active_task_id" > "$active_task_file"
  if [[ -n "$active_issue_number" ]]; then
    printf '%s\n' "$active_issue_number" > "$active_issue_file"
  else
    : > "$active_issue_file"
  fi
  printf '%s\n' "$active_task_id" > "$project_task_file"
  if [[ "$current_active_task" != "$active_task_id" ]]; then
    echo "RUNTIME_V2_PRIMARY_ACTIVE_RECONCILED=1"
    echo "RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=$active_task_id"
    [[ -n "$active_issue_number" ]] && echo "RUNTIME_V2_PRIMARY_ACTIVE_ISSUE_NUMBER=$active_issue_number"
  fi
elif [[ "$active_count" == "0" ]]; then
  if [[ -n "$current_active_task" ]]; then
    claim_grace_sec="${RUNTIME_V2_ACTIVE_CLAIM_GRACE_SEC:-120}"
    if ! [[ "$claim_grace_sec" =~ ^[0-9]+$ ]]; then
      claim_grace_sec=120
    fi

    claim_epoch="$(read_int_file_or_default "$claim_epoch_file" "0")"
    now_epoch="$(date +%s)"
    if (( claim_grace_sec > 0 && claim_epoch > 0 && now_epoch >= claim_epoch )); then
      claim_age=$(( now_epoch - claim_epoch ))
      if (( claim_age < claim_grace_sec )); then
        echo "RUNTIME_V2_PRIMARY_ACTIVE_CLAIM_GRACE=1"
        echo "RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=${current_active_task}"
        echo "RUNTIME_V2_PRIMARY_ACTIVE_GRACE_LEFT_SEC=$(( claim_grace_sec - claim_age ))"
      else
        : > "$active_task_file"
        : > "$active_issue_file"
        : > "$project_task_file"
        echo "RUNTIME_V2_PRIMARY_ACTIVE_CLEARED=1"
        echo "RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=${current_active_task}"
      fi
    else
      : > "$active_task_file"
      : > "$active_issue_file"
      : > "$project_task_file"
      echo "RUNTIME_V2_PRIMARY_ACTIVE_CLEARED=1"
      echo "RUNTIME_V2_PRIMARY_ACTIVE_TASK_ID=${current_active_task}"
    fi
  fi
else
  echo "RUNTIME_V2_PRIMARY_ACTIVE_AMBIGUOUS=1"
  echo "RUNTIME_V2_PRIMARY_ACTIVE_COUNT=$active_count"
fi

if [[ "$review_count" == "1" ]]; then
  printf '%s\n' "$review_task_id" > "$review_task_file"
  : > "$review_item_file"
  if [[ -n "$review_issue_number" ]]; then
    printf '%s\n' "$review_issue_number" > "$review_issue_file"
  else
    : > "$review_issue_file"
  fi
  if [[ -n "$review_pr_number" ]]; then
    printf '%s\n' "$review_pr_number" > "$review_pr_file"
  else
    : > "$review_pr_file"
  fi
  : > "$review_branch_file"
  if [[ "$current_review_task" != "$review_task_id" ]]; then
    echo "RUNTIME_V2_PRIMARY_REVIEW_RECONCILED=1"
    echo "RUNTIME_V2_PRIMARY_REVIEW_TASK_ID=$review_task_id"
    [[ -n "$review_issue_number" ]] && echo "RUNTIME_V2_PRIMARY_REVIEW_ISSUE_NUMBER=$review_issue_number"
    [[ -n "$review_pr_number" ]] && echo "RUNTIME_V2_PRIMARY_REVIEW_PR_NUMBER=$review_pr_number"
  fi
elif [[ "$review_count" == "0" ]]; then
  if [[ -n "$current_review_task" ]]; then
    : > "$review_task_file"
    : > "$review_item_file"
    : > "$review_issue_file"
    : > "$review_pr_file"
    : > "$review_branch_file"
    echo "RUNTIME_V2_PRIMARY_REVIEW_CLEARED=1"
    echo "RUNTIME_V2_PRIMARY_REVIEW_TASK_ID=${current_review_task}"
  fi
else
  echo "RUNTIME_V2_PRIMARY_REVIEW_AMBIGUOUS=1"
  echo "RUNTIME_V2_PRIMARY_REVIEW_COUNT=$review_count"
fi

desired_waiting_mode=""
if [[ "$waiting_count" == "1" ]]; then
  desired_waiting_mode="human"
  printf '%s\n' "$waiting_task_id" > "$waiting_task_file"
  if [[ -n "$waiting_issue_number" ]]; then
    printf '%s\n' "$waiting_issue_number" > "$waiting_issue_file"
  else
    : > "$waiting_issue_file"
  fi
  if [[ -n "$waiting_comment_id" ]]; then
    printf '%s\n' "$waiting_comment_id" > "$waiting_question_file"
  else
    : > "$waiting_question_file"
  fi
  if [[ -n "$waiting_kind" ]]; then
    printf '%s\n' "$waiting_kind" > "$waiting_kind_file"
  else
    : > "$waiting_kind_file"
  fi
  printf '%s\n' "${waiting_pending_post:-0}" > "$waiting_pending_file"
  if [[ -n "$waiting_since" ]]; then
    printf '%s\n' "$waiting_since" > "$waiting_since_file"
  else
    : > "$waiting_since_file"
  fi
  if [[ -n "$waiting_comment_url" ]]; then
    printf '%s\n' "$waiting_comment_url" > "$waiting_comment_url_file"
  else
    : > "$waiting_comment_url_file"
  fi
  if [[ "$current_waiting_task" != "$waiting_task_id" ]]; then
    echo "RUNTIME_V2_PRIMARY_WAITING_RECONCILED=1"
    echo "RUNTIME_V2_PRIMARY_WAITING_TASK_ID=$waiting_task_id"
    [[ -n "$waiting_issue_number" ]] && echo "RUNTIME_V2_PRIMARY_WAITING_ISSUE_NUMBER=$waiting_issue_number"
    [[ -n "$waiting_comment_id" ]] && echo "RUNTIME_V2_PRIMARY_WAITING_COMMENT_ID=$waiting_comment_id"
    [[ -n "$waiting_kind" ]] && echo "RUNTIME_V2_PRIMARY_WAITING_KIND=$waiting_kind"
  fi
elif [[ "$review_count" == "1" && ( -n "$review_comment_id" || "${review_pending_post:-0}" == "1" ) ]]; then
  desired_waiting_mode="review"
  printf '%s\n' "$review_issue_number" > "$waiting_issue_file"
  printf '%s\n' "$review_task_id" > "$waiting_task_file"
  if [[ -n "$review_comment_id" ]]; then
    printf '%s\n' "$review_comment_id" > "$waiting_question_file"
  else
    printf '0\n' > "$waiting_question_file"
  fi
  printf '%s\n' "REVIEW_FEEDBACK" > "$waiting_kind_file"
  printf '%s\n' "${review_pending_post:-0}" > "$waiting_pending_file"
  if [[ -n "$review_since" ]]; then
    printf '%s\n' "$review_since" > "$waiting_since_file"
  else
    : > "$waiting_since_file"
  fi
  if [[ -n "$review_comment_url" ]]; then
    printf '%s\n' "$review_comment_url" > "$waiting_comment_url_file"
  else
    : > "$waiting_comment_url_file"
  fi
  if [[ "$current_waiting_task" != "$review_task_id" || "$current_waiting_kind" != "REVIEW_FEEDBACK" ]]; then
    echo "RUNTIME_V2_PRIMARY_REVIEW_WAIT_RECONCILED=1"
    echo "RUNTIME_V2_PRIMARY_WAITING_TASK_ID=$review_task_id"
    [[ -n "$review_issue_number" ]] && echo "RUNTIME_V2_PRIMARY_WAITING_ISSUE_NUMBER=$review_issue_number"
    [[ -n "$review_comment_id" ]] && echo "RUNTIME_V2_PRIMARY_WAITING_COMMENT_ID=$review_comment_id"
  fi
elif [[ "$waiting_count" == "0" ]]; then
  if [[ -n "$current_waiting_task" ]]; then
    : > "$waiting_issue_file"
    : > "$waiting_task_file"
    : > "$waiting_question_file"
    : > "$waiting_kind_file"
    : > "$waiting_pending_file"
    : > "$waiting_since_file"
    : > "$waiting_comment_url_file"
    echo "RUNTIME_V2_PRIMARY_WAITING_CLEARED=1"
    echo "RUNTIME_V2_PRIMARY_WAITING_TASK_ID=${current_waiting_task}"
  fi
else
  echo "RUNTIME_V2_PRIMARY_WAITING_AMBIGUOUS=1"
  echo "RUNTIME_V2_PRIMARY_WAITING_COUNT=$waiting_count"
fi
