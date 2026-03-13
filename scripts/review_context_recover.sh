#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

CODEX_DIR="$(codex_export_state_dir)"
STATE_TMP_DIR="$(codex_resolve_state_tmp_dir "$CODEX_DIR")"
mkdir -p "$STATE_TMP_DIR"

codex_resolve_flow_config

REPO="$FLOW_GITHUB_REPO"
review_task_file="${CODEX_DIR}/daemon_review_task_id.txt"
review_item_file="${CODEX_DIR}/daemon_review_item_id.txt"
review_issue_file="${CODEX_DIR}/daemon_review_issue_number.txt"
review_pr_file="${CODEX_DIR}/daemon_review_pr_number.txt"
review_branch_file="${CODEX_DIR}/daemon_review_branch_name.txt"
active_task_file="${CODEX_DIR}/daemon_active_task.txt"
active_item_file="${CODEX_DIR}/daemon_active_item_id.txt"
active_issue_file="${CODEX_DIR}/daemon_active_issue_number.txt"
waiting_issue_file="${CODEX_DIR}/daemon_waiting_issue_number.txt"
waiting_task_file="${CODEX_DIR}/daemon_waiting_task_id.txt"
waiting_kind_file="${CODEX_DIR}/daemon_waiting_kind.txt"
waiting_since_file="${CODEX_DIR}/daemon_waiting_since_utc.txt"
waiting_question_id_file="${CODEX_DIR}/daemon_waiting_question_comment_id.txt"
waiting_comment_url_file="${CODEX_DIR}/daemon_waiting_comment_url.txt"
waiting_pending_post_file="${CODEX_DIR}/daemon_waiting_pending_post.txt"
project_task_file="${CODEX_DIR}/project_task_id.txt"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/review_context_recover.sh --pr-number <n> --pr-url <url> [options]

Options:
  --task-id <id>
  --issue-number <n>
  --item-id <id>
  --branch <name>
  --pr-title <title>
  --help
EOF
}

read_if_present() {
  local file_path="$1"
  [[ -s "$file_path" ]] || return 1
  cat "$file_path"
}

emit_nonempty_lines() {
  local text="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line"
  done <<< "$text"
}

task_id=""
issue_number=""
item_id=""
task_branch=""
pr_title=""
pr_number=""
pr_url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      task_id="${2:-}"
      shift 2
      ;;
    --issue-number)
      issue_number="${2:-}"
      shift 2
      ;;
    --item-id)
      item_id="${2:-}"
      shift 2
      ;;
    --branch)
      task_branch="${2:-}"
      shift 2
      ;;
    --pr-title)
      pr_title="${2:-}"
      shift 2
      ;;
    --pr-number)
      pr_number="${2:-}"
      shift 2
      ;;
    --pr-url)
      pr_url="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$pr_number" || -z "$pr_url" ]]; then
  usage
  exit 1
fi

if [[ -z "$task_id" ]]; then
  task_id="$(read_if_present "$active_task_file" || true)"
fi
if [[ -z "$task_id" ]]; then
  task_id="$(read_if_present "$project_task_file" || true)"
fi
if [[ -z "$issue_number" ]]; then
  issue_number="$(read_if_present "$active_issue_file" || true)"
fi
if [[ -z "$item_id" ]]; then
  item_id="$(read_if_present "$active_item_file" || true)"
fi
if [[ -z "$task_id" && "$pr_title" =~ (ISSUE-[0-9]+) ]]; then
  task_id="${BASH_REMATCH[1]}"
fi
if [[ -z "$issue_number" && "$task_id" =~ ISSUE-([0-9]+) ]]; then
  issue_number="${BASH_REMATCH[1]}"
fi
if [[ -z "$task_id" && -n "$issue_number" ]]; then
  task_id="ISSUE-${issue_number}"
fi

if [[ -z "$task_id" || -z "$issue_number" ]]; then
  echo "REVIEW_CONTEXT_RECOVER_SKIPPED=MISSING_TASK_OR_ISSUE"
  echo "RECOVER_TASK_ID=${task_id}"
  echo "RECOVER_ISSUE_NUMBER=${issue_number}"
  exit 1
fi

comment_body="$(cat <<EOF
CODEX_SIGNAL: AGENT_IN_REVIEW
CODEX_TASK: ${task_id}
CODEX_PR_NUMBER: ${pr_number}
CODEX_EXPECT: USER_REVIEW

Работу по задаче завершил, PR готов к проверке.
Жду твою проверку и решение по PR: ${pr_url}
EOF
)"

comment_id=""
comment_url=""
pending_post="0"

comments_json="$(
  "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
    gh api "repos/${REPO}/issues/${issue_number}/comments?per_page=100"
)"

comment_id="$(
  printf '%s' "$comments_json" |
    jq -r --arg pr "$pr_number" '
      [ .[]
        | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_IN_REVIEW$")))
        | select(((.body // "") | test("(?m)^CODEX_PR_NUMBER: " + $pr + "$")))
      ] | last | .id // empty
    '
)"
comment_url="$(
  printf '%s' "$comments_json" |
    jq -r --arg pr "$pr_number" '
      [ .[]
        | select(((.body // "") | test("(?m)^CODEX_SIGNAL: AGENT_IN_REVIEW$")))
        | select(((.body // "") | test("(?m)^CODEX_PR_NUMBER: " + $pr + "$")))
      ] | last | .html_url // empty
    '
)"

if [[ -n "$comment_id" ]]; then
  echo "REVIEW_CONTEXT_RECOVER_COMMENT_REUSED=1"
else
  comment_json=""
  err_file="$(mktemp "${STATE_TMP_DIR}/review_recover_gh_err.XXXXXX")"
  if comment_json="$(
    "${CODEX_SHARED_SCRIPTS_DIR}/gh_retry.sh" \
      gh api "repos/${REPO}/issues/${issue_number}/comments" \
      -f body="$comment_body" 2>"$err_file"
  )"; then
    if [[ -s "$err_file" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line"
      done < "$err_file"
    fi
    rm -f "$err_file"
    comment_id="$(printf '%s' "$comment_json" | jq -r '.id // empty')"
    comment_url="$(printf '%s' "$comment_json" | jq -r '.html_url // empty')"
    echo "REVIEW_CONTEXT_RECOVER_COMMENT_POSTED=1"
  else
    rc=$?
    comment_err="$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file"
    if [[ "$rc" -eq 75 ]]; then
      tmp_body="$(mktemp "${STATE_TMP_DIR}/review_recover_body.XXXXXX")"
      printf '%s\n' "$comment_body" > "$tmp_body"
      if queue_out="$(
        "${CODEX_SHARED_SCRIPTS_DIR}/github_outbox.sh" \
          enqueue_issue_comment \
          "$REPO" \
          "$issue_number" \
          "$tmp_body" \
          "$task_id" \
          "REVIEW_FEEDBACK" \
          "1" 2>&1
      )"; then
        rm -f "$tmp_body"
        emit_nonempty_lines "$queue_out"
        pending_post="1"
        echo "REVIEW_CONTEXT_RECOVER_COMMENT_QUEUED_OUTBOX=1"
      else
        qrc=$?
        rm -f "$tmp_body"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "REVIEW_CONTEXT_RECOVER_OUTBOX_ERROR(rc=$qrc): $line"
        done <<< "$queue_out"
        exit "$qrc"
      fi
    else
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "REVIEW_CONTEXT_RECOVER_COMMENT_ERROR(rc=$rc): $line"
      done <<< "$comment_err"
      exit "$rc"
    fi
  fi
fi

printf '%s\n' "$task_id" > "$review_task_file"
printf '%s\n' "$issue_number" > "$review_issue_file"
printf '%s\n' "$pr_number" > "$review_pr_file"
if [[ -n "$item_id" ]]; then
  printf '%s\n' "$item_id" > "$review_item_file"
else
  : > "$review_item_file"
fi
if [[ -n "$task_branch" ]]; then
  printf '%s\n' "$task_branch" > "$review_branch_file"
else
  : > "$review_branch_file"
fi

printf '%s\n' "$issue_number" > "$waiting_issue_file"
printf '%s\n' "$task_id" > "$waiting_task_file"
printf '%s\n' "REVIEW_FEEDBACK" > "$waiting_kind_file"
if [[ -n "$comment_id" ]]; then
  printf '%s\n' "$comment_id" > "$waiting_question_id_file"
else
  printf '0\n' > "$waiting_question_id_file"
fi
if [[ -n "$comment_url" ]]; then
  printf '%s\n' "$comment_url" > "$waiting_comment_url_file"
else
  : > "$waiting_comment_url_file"
fi
printf '%s\n' "$pending_post" > "$waiting_pending_post_file"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$waiting_since_file"

: > "$active_task_file"
: > "$active_item_file"
: > "$active_issue_file"

echo "REVIEW_CONTEXT_RECOVERED=1"
echo "REVIEW_CONTEXT_TASK_ID=$task_id"
echo "REVIEW_CONTEXT_ISSUE_NUMBER=$issue_number"
echo "REVIEW_CONTEXT_PR_NUMBER=$pr_number"
[[ -n "$comment_id" ]] && echo "REVIEW_CONTEXT_COMMENT_ID=$comment_id"
[[ -n "$comment_url" ]] && echo "REVIEW_CONTEXT_COMMENT_URL=$comment_url"
echo "WAIT_REVIEW_FEEDBACK=1"
